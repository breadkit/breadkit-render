# frozen_string_literal: true

module Breadkit
  module Render
    # Components are drawn once, with terminals tied to resolved net names.
    class SchematicRenderer
      NET_COLORS = %w[#d96a72 #5b9de3 #52b99a #ba8bd1 #d4a658 #5db6bf].freeze
      TOP = 170
      NET_GAP = 150
      DEVICE_LEFT = 210
      DEVICE_GAP = 220
      BLOCK_GAP = 590
      BLOCK_WIDTH = 250
      PIN_GAP = 28

      def render(circuit, theme: "light", state: nil)
        raise ArgumentError, "unknown schematic theme: #{theme}" unless %w[light dark print].include?(theme)

        colors = palette(theme)
        nets = circuit.nets(state)
        components = component_devices(circuit)
        devices = supply_devices(circuit) + components.select { |component| component[:terminals].length == 2 }
        blocks = components.reject { |component| component[:terminals].length == 2 }
        device_terminals = devices.flat_map { |device| device[:terminals].map { |terminal| terminal[:id] } }
        bus_nets = nets.select { |net| (net.members & device_terminals).any? }
        net_by_terminal = nets.each_with_object({}) { |net, index| net.members.each { |member| index[member] = net } }
        net_rows = bus_nets.each_with_index.to_h { |net, index| [net.name, TOP + index * NET_GAP] }
        (devices + blocks).each do |device|
          device[:terminals].each do |terminal|
            net = net_by_terminal[terminal[:id]]
            raise Error, "schematic cannot resolve terminal #{terminal[:id]}" unless net

            terminal[:net] = net.name
            terminal[:y] = net_rows[net.name]
            terminal[:isolated] = net.members.length == 1 && Array(net.labels).empty?
          end
        end
        devices.each_with_index do |device, index|
          device[:x] = DEVICE_LEFT + index * DEVICE_GAP
          if device[:terminals].map { |terminal| terminal[:net] }.uniq.length != 2
            raise Error, "schematic cannot separate both terminals of #{device[:ref]} on the same net"
          end
          device[:terminals].sort_by! { |terminal| terminal[:y] }
          device[:symbol_y] = device[:terminals].first[:y] + NET_GAP / 2
        end
        width = [900, DEVICE_LEFT + devices.length * DEVICE_GAP].max
        height = [360, TOP + ([bus_nets.length - 1, 0].max * NET_GAP) + 120].max
        if blocks.any?
          block_left = devices.empty? ? DEVICE_LEFT : devices.last[:x] + 170
          width = [width, block_left + ([blocks.length, 2].min - 1) * BLOCK_GAP + BLOCK_WIDTH + 120].max
          block_y = TOP
          blocks.each_slice(2) do |row|
            row.each_with_index { |block, index| block[:x], block[:y] = block_left + index * BLOCK_GAP, block_y }
            block_y += row.map { |block| block_height(block) }.max + 56
          end
          height = [height, block_y].max
        end

        svg = []
        svg << %(<?xml version="1.0" encoding="UTF-8"?>)
        svg << %(<svg xmlns="http://www.w3.org/2000/svg" width="#{width}" height="#{height}" viewBox="0 0 #{width} #{height}" role="img" aria-label="Circuit schematic" data-view="schematic" data-theme="#{theme}"#{state&.name ? %( data-state="#{xml(state.name)}") : ""}>)
        svg << %(<title>Circuit schematic</title>)
        svg << %(<desc>#{xml((["Each component is drawn once. Colored wires and matching net labels connect terminals. Board hole locations are omitted."] + nets.map { |net| "#{net.name}: #{net.members.join(', ')}" }).join(' '))}</desc>)
        svg << %(<rect width="#{width}" height="#{height}" fill="#{colors[:background]}"/>)
        svg << %(<g font-family="Arial, Helvetica, sans-serif" fill="#{colors[:text]}">)
        svg << %(<text x="48" y="40" fill="#{colors[:muted]}" font-size="11" font-weight="700" letter-spacing="2.4">BREADKIT / SCHEMATIC</text>)
        svg << %(<text x="48" y="80" font-size="29" font-weight="700">Circuit schematic</text>)
        connected_nets = nets.count { |net| net.members.length > 1 || Array(net.labels).any? }
        isolated_nets = nets.length - connected_nets
        svg << %(<text x="#{width - 48}" y="78" text-anchor="end" fill="#{colors[:muted]}" font-size="12">#{devices.length + blocks.length} symbols  ·  #{connected_nets} connected nets#{isolated_nets.positive? ? "  ·  #{isolated_nets} isolated" : ""}#{state&.name ? "  ·  #{xml(state.name)} closed" : ""}</text>)
        svg << %(<line x1="48" y1="99" x2="#{width - 48}" y2="99" stroke="#{colors[:border]}"/>)
        svg << %(<g id="nets">)
        bus_nets.each do |net|
          index = nets.index(net)
          svg << net_svg(net, net_rows.fetch(net.name), devices, NET_COLORS[index % NET_COLORS.length], colors)
        end
        svg << %(</g><g id="devices">)
        devices.each do |device|
          svg << device_svg(device, NET_COLORS, nets, colors)
        end
        svg << %(</g>)
        if blocks.any?
          svg << %(<g id="multi-pin-devices">)
          svg << %(<text x="#{blocks.first[:x]}" y="#{blocks.first[:y] - 32}" fill="#{colors[:muted]}" font-size="12" font-weight="700" letter-spacing="1.2">MATCHING NET LABELS CONNECT PINS</text>)
          blocks.each { |block| svg << block_svg(block, nets, colors) }
          svg << %(</g>)
        end
        svg << %(</g></svg>)
        svg.join("\n")
      end

      private

      def component_devices(circuit)
        circuit.components.values.map do |component|
          pins = component.pins.values
          raise Error, "schematic cannot draw #{component.ref} without terminals" if pins.empty?

          shape = component.part.data.dig("render", "shape")
          detail = component.value || component.part.data.dig("render", "label") || component.part.id
          { ref: component.ref, shape: shape, detail: detail,
            terminals: pins.map { |pin| { id: "#{component.ref}.#{pin.name}", name: pin.name } } }
        end
      end

      def block_height(block)
        66 + ((block[:terminals].length + 1) / 2) * PIN_GAP
      end

      def block_svg(block, nets, colors)
        x, y = block.values_at(:x, :y)
        height = block_height(block)
        kind = %w[offboard module].include?(block[:shape]) ? "module" : "ic"
        half = (block[:terminals].length + 1) / 2
        svg = [%(<g data-ref="#{xml(block[:ref])}" data-symbol="#{kind}">)]
        svg << %(<title>#{xml(block[:ref])}: #{xml(block[:detail])}</title>)
        svg << %(<rect x="#{x}" y="#{y}" width="#{BLOCK_WIDTH}" height="#{height}" rx="8" fill="#{colors[:surface]}" stroke="#{colors[:border]}" stroke-width="2"/>)
        svg << %(<text x="#{x + 14}" y="#{y + 24}" font-size="16" font-weight="700">#{xml(block[:ref])}</text>)
        svg << %(<text x="#{x + BLOCK_WIDTH - 14}" y="#{y + 24}" text-anchor="end" fill="#{colors[:muted]}" font-size="12">#{xml(block[:detail])}</text>)
        svg << %(<line x1="#{x}" y1="#{y + 36}" x2="#{x + BLOCK_WIDTH}" y2="#{y + 36}" stroke="#{colors[:border]}"/>)
        block[:terminals].each_with_index do |terminal, index|
          left = index < half
          row = left ? index : block[:terminals].length - index - 1
          pin_y = y + 61 + row * PIN_GAP
          net_index = nets.index { |net| net.name == terminal[:net] }
          color = terminal[:isolated] ? colors[:muted] : NET_COLORS[net_index % NET_COLORS.length]
          edge = left ? x : x + BLOCK_WIDTH
          tip = left ? x - 24 : edge + 24
          pin_x = left ? x + 12 : edge - 12
          net_x = left ? tip - 8 : tip + 8
          svg << %(<path d="M #{edge} #{pin_y} H #{tip}" fill="none" stroke="#{color}" stroke-width="2.5" data-terminal="#{xml(terminal[:id])}" data-net="#{xml(terminal[:net])}"#{terminal[:isolated] ? %( data-unconnected="true") : ''}/>)
          svg << %(<circle cx="#{tip}" cy="#{pin_y}" r="3" fill="#{color}"/>)
          svg << %(<text x="#{pin_x}" y="#{pin_y + 4}" text-anchor="#{left ? 'start' : 'end'}" font-size="11" data-pin-label="#{xml(terminal[:id])}">#{xml(terminal[:name])}</text>)
          unless terminal[:isolated]
            svg << %(<text x="#{net_x}" y="#{pin_y + 4}" text-anchor="#{left ? 'end' : 'start'}" fill="#{color}" font-size="11" font-weight="700" data-pin-net="#{xml(terminal[:id])}">#{xml(terminal[:net])}</text>)
          end
        end
        svg << %(</g>)
        svg.join
      end

      def supply_devices(circuit)
        circuit.supplies.map do |supply|
          voltage = supply.voltage_range ? supply.voltage_range.join("–") : format("%g", supply.voltage)
          { ref: supply.name, shape: "voltage-source", detail: "#{voltage} V",
            terminals: [{ id: "#{supply.name}.+", name: "+" }, { id: "#{supply.name}.-", name: "−" }] }
        end
      end

      def net_svg(net, y, devices, accent, colors)
        xs = devices.filter_map { |device| device[:x] if device[:terminals].any? { |terminal| terminal[:net] == net.name } }
        x1, x2 = xs.empty? ? [180, 240] : [xs.min - 20, xs.max + 20]
        crossings = devices.filter_map do |device|
          top, bottom = device[:terminals].map { |terminal| terminal[:y] }
          device[:x] if top < y && y < bottom && device[:x].between?(x1 + 9, x2 - 9)
        end.sort
        path = "M #{x1} #{y}"
        crossings.each { |x| path << " H #{x - 9} Q #{x} #{y - 12} #{x + 9} #{y}" }
        path << " H #{x2}"
        %(<path d="#{path}" fill="none" stroke="#{accent}" stroke-width="2.5" stroke-linecap="round" data-net="#{xml(net.name)}" data-crossovers="#{crossings.length}"/>) +
          %(<text x="#{x1 - 12}" y="#{y - 15}" text-anchor="end" fill="#{colors[:text]}" font-size="13" font-weight="700" data-net-label="#{xml(net.name)}">#{xml(net.name)}</text>)
      end

      def device_svg(device, net_colors, nets, colors)
        x, y = device.values_at(:x, :symbol_y)
        first, last = device[:terminals]
        top_color = net_colors[nets.index { |net| net.name == first[:net] } % net_colors.length]
        bottom_color = net_colors[nets.index { |net| net.name == last[:net] } % net_colors.length]
        shape = device[:shape]
        kind = case shape
        when "led_5mm" then "led"
        when "voltage-source" then "voltage-source"
        when "resistor", "diode", "capacitor", "electrolytic" then shape
        else "two-terminal"
        end
        svg = [%(<g data-ref="#{xml(device[:ref])}" data-symbol="#{kind}">)]
        svg << %(<title>#{xml(device[:ref])}: #{xml(device[:detail])}</title>)
        svg << terminal_wire(first, x, y - 20, top_color)
        svg << terminal_wire(last, x, y + 20, bottom_color)
        svg << symbol_svg(device, kind, colors)
        label_x = x + (kind == "led" ? 55 : 39)
        svg << %(<text x="#{label_x}" y="#{y - 3}" font-size="14" font-weight="700">#{xml(device[:ref])}</text>)
        svg << %(<text x="#{label_x}" y="#{y + 15}" fill="#{colors[:muted]}" font-size="12">#{xml(device[:detail])}</text>)
        svg << %(</g>)
        svg.join
      end

      def terminal_wire(terminal, x, symbol_end, color)
        y = terminal[:y]
        %(<path d="M #{x} #{y} V #{symbol_end}" fill="none" stroke="#{color}" stroke-width="2.5" data-terminal="#{xml(terminal[:id])}" data-net="#{xml(terminal[:net])}"/>) +
          %(<circle cx="#{x}" cy="#{y}" r="4" fill="#{color}"/>)
      end

      def symbol_svg(device, kind, colors)
        x, y = device.values_at(:x, :symbol_y)
        stroke = colors[:text]
        case kind
        when "resistor"
          points = [[x, y - 20], [x - 9, y - 15], [x + 9, y - 8], [x - 9, y],
                    [x + 9, y + 8], [x - 9, y + 15], [x, y + 20]]
          %(<polyline points="#{points.map { |point| point.join(',') }.join(' ')}" fill="none" stroke="#{stroke}" stroke-width="2.5" stroke-linejoin="round"/>)
        when "voltage-source"
          plus_top = device[:terminals].first[:name] == "+"
          %(<circle cx="#{x}" cy="#{y}" r="20" fill="#{colors[:background]}" stroke="#{stroke}" stroke-width="2.5"/>) +
            %(<text x="#{x}" y="#{y - 5}" text-anchor="middle" font-size="15" font-weight="700">#{plus_top ? '+' : '−'}</text>) +
            %(<text x="#{x}" y="#{y + 14}" text-anchor="middle" font-size="15" font-weight="700">#{plus_top ? '−' : '+'}</text>)
        when "led", "diode"
          diode_svg(device, colors, led: kind == "led")
        when "capacitor", "electrolytic"
          %(<path d="M #{x} #{y - 20} V #{y - 6} M #{x - 14} #{y - 6} H #{x + 14} M #{x - 14} #{y + 6} H #{x + 14} M #{x} #{y + 6} V #{y + 20}" fill="none" stroke="#{stroke}" stroke-width="2.5"/>)
        else
          %(<rect x="#{x - 16}" y="#{y - 20}" width="32" height="40" rx="3" fill="#{colors[:background]}" stroke="#{stroke}" stroke-width="2.5"/>)
        end
      end

      def diode_svg(device, colors, led:)
        x, y = device.values_at(:x, :symbol_y)
        cathode_top = device[:terminals].first[:name].to_s.downcase == "cathode"
        triangle = if cathode_top
          "#{x - 12},#{y + 9} #{x + 12},#{y + 9} #{x},#{y - 8}"
        else
          "#{x - 12},#{y - 9} #{x + 12},#{y - 9} #{x},#{y + 8}"
        end
        bar_y = cathode_top ? y - 10 : y + 10
        svg = %(<polygon points="#{triangle}" fill="#{colors[:background]}" stroke="#{colors[:text]}" stroke-width="2.5"/>)
        svg << %(<path d="M #{x - 13} #{bar_y} H #{x + 13} M #{x} #{y - 20} V #{y - 10} M #{x} #{y + 10} V #{y + 20}" fill="none" stroke="#{colors[:text]}" stroke-width="2.5"/>)
        if led
          svg << %(<path d="M #{x + 16} #{y - 2} l 13 -13 m -5 0 h 5 v 5 M #{x + 20} #{y + 8} l 13 -13 m -5 0 h 5 v 5" fill="none" stroke="#{colors[:text]}" stroke-width="1.8"/>)
        end
        svg
      end

      def palette(theme)
        return { background: "#ffffff", surface: "#ffffff", border: "#b8c0ca", text: "#111827", muted: "#4b5563" } if theme == "print"
        return { background: "#0d1420", surface: "#192437", border: "#35435a", text: "#f2f6fc", muted: "#a5b4c8" } if theme == "dark"

        { background: "#f4f7fb", surface: "#ffffff", border: "#d6deea", text: "#172338", muted: "#63738a" }
      end

      def xml(value)
        CGI.escapeHTML(value.to_s)
      end
    end
  end
end
