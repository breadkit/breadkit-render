# frozen_string_literal: true

module Breadkit
  module Render
    # Shows each resolved net as a bus with its connected physical terminals.
    # This layout keeps large circuits readable without crossing unrelated nets.
    class NetlistRenderer
      COLORS = %w[#d85e65 #4f8fd6 #319b7d #aa75c7 #c58a37 #4a9da7 #a0b95c #d57da8
                  #8499df #d67c53 #55b58c #c299d3].freeze
      WIDTH = 1120
      LEFT = 48
      CARD_WIDTH = WIDTH - LEFT * 2
      TERMINALS_PER_ROW = 5

      def render(circuit, theme: "light", state: nil)
        raise ArgumentError, "unknown netlist theme: #{theme}" unless %w[light dark print].include?(theme)

        colors = palette(theme)
        nets = circuit.nets(state)
        devices = component_devices(circuit) + supply_devices(circuit)
        terminals = devices.flat_map { |device| device[:terminals] }
        terminal_nets = nets.each_with_object({}) { |net, index| net.members.each { |member| index[member] = net } }
        terminals.each do |terminal|
          raise Error, "netlist cannot resolve terminal #{terminal[:id]}" unless terminal_nets[terminal[:id]]
        end

        device_rows = (devices.length.to_f / 3).ceil
        net_y = 116 + device_rows * 88 + 58
        net_y += 36 if devices.empty?
        net_layout = nets.map do |net|
          members = terminals.select { |terminal| terminal_nets[terminal[:id]] == net }
          rows = (members.length.to_f / TERMINALS_PER_ROW).ceil
          height = 82 + [rows, 1].max * 66
          layout = { net: net, terminals: members, y: net_y, height: height }
          net_y += height + 16
          layout
        end
        height = [net_y + 32, 300].max

        lines = []
        lines << %(<?xml version="1.0" encoding="UTF-8"?>)
        lines << %(<svg xmlns="http://www.w3.org/2000/svg" width="#{WIDTH}" height="#{height}" viewBox="0 0 #{WIDTH} #{height}" role="img" aria-label="Circuit netlist" data-view="netlist" data-theme="#{theme}"#{state&.name ? %( data-state="#{xml(state.name)}") : ""}>)
        lines << %(<title>Circuit netlist</title>)
        lines << %(<desc>#{xml((["Each colored bus is one resolved net. Terminals on the same bus are connected."] + nets.map { |net| "#{net.name}: #{net.members.join(', ')}" }).join(' '))}</desc>)
        lines << %(<rect width="#{WIDTH}" height="#{height}" fill="#{colors[:background]}"/>)
        lines << %(<g font-family="Arial, Helvetica, sans-serif">)
        lines << %(<text x="48" y="39" fill="#{colors[:muted]}" font-size="11" font-weight="700" letter-spacing="2.4">BREADKIT / NETLIST</text>)
        lines << %(<text x="48" y="76" fill="#{colors[:text]}" font-size="29" font-weight="700">Circuit netlist</text>)
        lines << %(<text x="1072" y="75" text-anchor="end" fill="#{colors[:muted]}" font-size="12">#{devices.length} devices  ·  #{nets.length} nets#{state&.name ? "  ·  #{xml(state.name)} closed" : ""}</text>)
        lines << %(<line x1="48" y1="93" x2="1072" y2="93" stroke="#{colors[:border]}"/>)

        lines << %(<g id="devices">)
        devices.each_with_index do |device, index|
          x = LEFT + (index % 3) * 346
          y = 116 + (index / 3) * 88
          lines << %(<g data-ref="#{xml(device[:ref])}">)
          lines << %(<rect x="#{x}" y="#{y}" width="328" height="70" rx="12" fill="#{colors[:card]}" stroke="#{colors[:border]}"/>)
          lines << %(<text x="#{x + 18}" y="#{y + 30}" fill="#{colors[:text]}" font-size="17" font-weight="700">#{xml(device[:ref])}</text>)
          lines << %(<text x="#{x + 18}" y="#{y + 51}" fill="#{colors[:muted]}" font-size="11">#{xml(device[:detail])}  ·  #{device[:terminals].length} pins</text>)
          lines << %(</g>)
        end
        lines << %(</g>)
        lines << %(<text x="48" y="#{net_layout.first ? net_layout.first[:y] - 18 : net_y - 18}" fill="#{colors[:muted]}" font-size="11" font-weight="700" letter-spacing="1.8">RESOLVED NETS</text>)

        lines << %(<g id="nets">)
        net_layout.each_with_index do |layout, index|
          net = layout[:net]
          y = layout[:y]
          accent = COLORS[index % COLORS.length]
          lines << %(<g data-net="#{xml(net.name)}">)
          lines << %(<rect x="#{LEFT}" y="#{y}" width="#{CARD_WIDTH}" height="#{layout[:height]}" rx="12" fill="#{colors[:card]}" stroke="#{colors[:border]}"/>)
          lines << %(<rect x="#{LEFT}" y="#{y}" width="5" height="#{layout[:height]}" rx="2.5" fill="#{accent}"/>)
          lines << %(<text x="#{LEFT + 22}" y="#{y + 31}" fill="#{colors[:text]}" font-size="18" font-weight="700">#{xml(net.name)}</text>)
          lines << %(<text x="#{LEFT + 22}" y="#{y + 51}" fill="#{colors[:muted]}" font-size="11">#{layout[:terminals].length} terminals  ·  #{net.holes.length} holes</text>)
          lines << %(<line x1="#{LEFT + 20}" y1="#{y + 61}" x2="#{LEFT + CARD_WIDTH - 20}" y2="#{y + 61}" stroke="#{colors[:border]}"/>)
          if layout[:terminals].empty?
            lines << %(<text x="#{LEFT + 25}" y="#{y + 105}" fill="#{colors[:muted]}" font-size="12">No device terminals on this net</text>)
          else
            draw_terminals(lines, layout, accent, colors)
          end
          lines << %(</g>)
        end
        lines << %(</g>)
        lines << %(</g></svg>)
        lines.join("\n")
      end

      private

      def draw_terminals(lines, layout, accent, colors)
        y = layout[:y]
        rows = (layout[:terminals].length.to_f / TERMINALS_PER_ROW).ceil
        lines << %(<line x1="#{LEFT + 27}" y1="#{y + 77}" x2="#{LEFT + 27}" y2="#{y + 77 + (rows - 1) * 66}" stroke="#{accent}" stroke-width="2"/>) if rows > 1
        layout[:terminals].each_slice(TERMINALS_PER_ROW).with_index do |terminals, row|
          bus_y = y + 77 + row * 66
          last_x = LEFT + 35 + (terminals.length - 1) * 196 + 90
          lines << %(<line x1="#{LEFT + 27}" y1="#{bus_y}" x2="#{last_x}" y2="#{bus_y}" stroke="#{accent}" stroke-width="2"/>)
          terminals.each_with_index do |terminal, column|
            chip_x = LEFT + 35 + column * 196
            center_x = chip_x + 90
            lines << %(<path d="M #{center_x} #{bus_y} V #{bus_y + 13}" stroke="#{accent}" stroke-width="2" data-terminal="#{xml(terminal[:id])}" data-net="#{xml(layout[:net].name)}"/>)
            lines << %(<circle cx="#{center_x}" cy="#{bus_y}" r="3" fill="#{accent}"/>)
            lines << %(<rect x="#{chip_x}" y="#{bus_y + 13}" width="180" height="42" rx="8" fill="#{colors[:chip]}" stroke="#{colors[:border]}"/>)
            lines << %(<text x="#{chip_x + 11}" y="#{bus_y + 39}" fill="#{colors[:text]}" font-size="13" font-weight="700">#{xml(terminal[:ref])}</text>)
            lines << %(<text x="#{chip_x + 169}" y="#{bus_y + 39}" text-anchor="end" fill="#{colors[:muted]}" font-size="12">#{xml(terminal[:pin])}</text>)
          end
        end
      end

      def component_devices(circuit)
        circuit.components.values.map do |component|
          { ref: component.ref, detail: component.part.id,
            terminals: component.pins.values.map { |pin| { id: "#{component.ref}.#{pin.name}", ref: component.ref, pin: pin.name } } }
        end
      end

      def supply_devices(circuit)
        circuit.supplies.map do |supply|
          voltage = supply.voltage_range ? "#{supply.voltage_range.join('–')} V" : format("%g V", supply.voltage)
          { ref: supply.name, detail: "Power supply · #{voltage}",
            terminals: [{ id: "#{supply.name}.+", ref: supply.name, pin: "+" },
                        { id: "#{supply.name}.-", ref: supply.name, pin: "−" }] }
        end
      end

      def palette(theme)
        return { background: "#ffffff", card: "#ffffff", chip: "#ffffff", border: "#bec5cf", text: "#111827", muted: "#4b5563" } if theme == "print"
        return { background: "#0d1420", card: "#172233", chip: "#202d40", border: "#35435a", text: "#f2f6fc", muted: "#a5b4c8" } if theme == "dark"

        { background: "#f4f7fb", card: "#ffffff", chip: "#f1f5fa", border: "#d6deea", text: "#172338", muted: "#63738a" }
      end

      def xml(value)
        CGI.escapeHTML(value.to_s)
      end
    end
  end
end
