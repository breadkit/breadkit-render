# frozen_string_literal: true

require "json"

module Breadkit
  module Render
    class SvgRenderer
      PITCH = 10.0
      RAIL_PATTERNS = %w[+--+ +-+- -+-+ -++-].freeze
      OFFBOARD_PIN_PITCH = 1.0
      PALETTE = %w[#d62728 #1f77b4 #2ca02c #9467bd #ff7f0e #17becf].freeze
      MODULE_PIN_COLORS = {
        "power" => "#E24B4A", "ground" => "#888780", "clock" => "#EF9F27",
        "data" => "#378ADD", "interrupt" => "#D4537E", "address" => "#888780"
      }.freeze
      CSS_COLOR_NAMES = %w[
        aliceblue antiquewhite aqua aquamarine azure beige bisque black blanchedalmond blue blueviolet brown
        burlywood cadetblue chartreuse chocolate coral cornflowerblue cornsilk crimson cyan darkblue darkcyan
        darkgoldenrod darkgray darkgreen darkgrey darkkhaki darkmagenta darkolivegreen darkorange darkorchid darkred
        darksalmon darkseagreen darkslateblue darkslategray darkslategrey darkturquoise darkviolet deeppink deepskyblue
        dimgray dimgrey dodgerblue firebrick floralwhite forestgreen fuchsia gainsboro ghostwhite gold goldenrod gray
        green greenyellow grey honeydew hotpink indianred indigo ivory khaki lavender lavenderblush lawngreen
        lemonchiffon lightblue lightcoral lightcyan lightgoldenrodyellow lightgray lightgreen lightgrey lightpink
        lightsalmon lightseagreen lightskyblue lightslategray lightslategrey lightsteelblue lightyellow lime limegreen
        linen magenta maroon mediumaquamarine mediumblue mediumorchid mediumpurple mediumseagreen mediumslateblue
        mediumspringgreen mediumturquoise mediumvioletred midnightblue mintcream mistyrose moccasin navajowhite navy
        oldlace olive olivedrab orange orangered orchid palegoldenrod palegreen paleturquoise palevioletred papayawhip
        peachpuff peru pink plum powderblue purple rebeccapurple red rosybrown royalblue saddlebrown salmon sandybrown
        seagreen seashell sienna silver skyblue slateblue slategray slategrey snow springgreen steelblue tan teal thistle
        tomato turquoise violet wheat white whitesmoke yellow yellowgreen
      ].freeze
      COLORS = {
        "light" => { board: "#f2f5f2", border: "#b8c4bc", groove: "#e0e6e2", hole: "#9aa69f", used_hole: "#394a40",
                     connected_hole: "#71877a", resistor_bg: "#f0d79c", resistor_border: "#654f36",
                     diode_bg: "#35383b", diode_border: "#191b1d", diode_mark: "#eeeeee",
                     dip_bg: "#33393d", dip_border: "#151719", dip_notch: "#aaaaaa", dip_text: "#ffffff",
                     switch_bg: "#ece7dd", switch_border: "#504c45", switch_button: "#c7c0b5", switch_button_border: "#6c655b",
                     text: "#25312b", label: "#627168", positive: "#cf5955", negative: "#71847e", negative_wire: "#315ea8", lead: "#68766f",
                     component_bg: "#e8eeea", component_border: "#aab7af", module_bg: "#f1efe8",
                     module_border: "#888780", muted: "#92918b", accent: "#1D6B45" },
        "dark" => { board: "#202a27", border: "#52625b", groove: "#141c19", hole: "#718178", used_hole: "#d4e2d9",
                    connected_hole: "#9bab9e", resistor_bg: "#6b6248", resistor_border: "#c9ac73",
                    diode_bg: "#4b5550", diode_border: "#aab7af", diode_mark: "#dde6df",
                    dip_bg: "#39433e", dip_border: "#91a199", dip_notch: "#c0cdc5", dip_text: "#e8efeb",
                    switch_bg: "#3d4540", switch_border: "#819188", switch_button: "#58665d", switch_button_border: "#a4b6a9",
                    text: "#e8efeb", label: "#c0cdc5", positive: "#ed7168", negative: "#99aaa4", negative_wire: "#76a9f2", lead: "#91a199",
                    component_bg: "#2d3935", component_border: "#607168", module_bg: "#343a3d",
                    module_border: "#687176", muted: "#889095", accent: "#8fbea1" },
        "print" => { board: "#ffffff", border: "#555555", groove: "#eeeeee", hole: "#aaaaaa", used_hole: "#333333",
                     connected_hole: "#777777", resistor_bg: "#dddddd", resistor_border: "#555555",
                     diode_bg: "#555555", diode_border: "#333333", diode_mark: "#ffffff",
                     dip_bg: "#555555", dip_border: "#222222", dip_notch: "#eeeeee", dip_text: "#ffffff",
                     switch_bg: "#eeeeee", switch_border: "#444444", switch_button: "#cccccc", switch_button_border: "#444444",
                     text: "#222222", label: "#444444", positive: "#333333", negative: "#777777", negative_wire: "#555555", lead: "#333333",
                     component_bg: "#f4f4f4", component_border: "#555555", module_bg: "#f4f4f4",
                     module_border: "#666666", muted: "#777777", accent: "#333333" }
      }.freeze

      def render(circuit, crop: "auto", theme: "light", orientation: "portrait", show_nets: false, legend: false, color_by: "wire", annotations: [], rail_pattern: nil, interactive_layers: true)
        @circuit, @theme, @orientation, @show_nets, @legend_enabled, @color_by, @annotations = circuit, theme.to_s, orientation.to_s, show_nets, legend, color_by, annotations
        @wire_indexes = circuit.wires.each_with_index.to_h
        @wires_by_id = circuit.wires.to_h { |wire| [wire.id, wire] }
        @rail_definitions = Array(circuit.board.definition.data["rails"]).to_h { |rail| [rail["id"].to_s, rail] }
        @wire_endpoint_refs = circuit.wires.each_with_object({}) { |wire, refs| refs[wire.from] = refs[wire.to] = true }
        @nets_by_member, @nets_by_hole = {}, {}
        circuit.nets.each do |net|
          net.members.each { |member| @nets_by_member[member] = net }
          net.holes.each { |hole| @nets_by_hole[hole] = net }
        end
        @net_indexes = circuit.nets.each_with_index.to_h
        @board_edge_wires = circuit.wires.select do |wire|
          wire.route == "edge" && !offboard_component(wire.from) && !offboard_component(wire.to)
        end
        @board_edge_indexes = @board_edge_wires.each_with_index.to_h
        @board_extents = { x: circuit.board.holes.values.map(&:x).minmax,
                           y: circuit.board.holes.values.map(&:y).minmax }
        @rail_y_extents = circuit.board.holes.values.select { |hole| hole.kind == :rail }.map(&:y).minmax
        @offboard_terminal_wires = {}
        @offboard_terminal_indexes = {}
        @offboard_terminal_breakouts = {}
        @offboard_rail_tracks = nil
        @offboard_layouts = {}
        @edge_breakout_offsets = @annotation_states = nil
        raise ArgumentError, "orientation must be portrait or landscape" unless %w[portrait landscape].include?(@orientation)
        @layers = if interactive_layers
          (circuit.wires.flat_map { |wire| layer_names(wire.layer) } +
            circuit.components.values.flat_map { |component| layer_names(read(component.attrs, "layer")) }).uniq
        else
          []
        end
        @layer_controls_height = 0
        @rail_pattern = rail_pattern&.to_s
        configure_rail_pattern

        @colors = COLORS.fetch(@theme, COLORS.fetch("light"))
        @conductive_holes = @nets_by_hole.keys.to_set
        @used_holes = (circuit.components.values.flat_map { |component| component.pins.values.map(&:hole_id) } +
                       circuit.wires.flat_map { |wire| [wire.from, wire.to].filter_map { |endpoint| circuit.board.hole(endpoint)&.id } } +
                       circuit.supplies.flat_map { |supply| [supply.plus, supply.minus] }).compact.to_set
        @view_box = view_box(crop)
        @layer_controls_height = layer_controls_height unless @layers.empty?
        left, top, width, height = @view_box
        extra_height = legend_height
        output_width, output_height, output_view_box = if @orientation == "portrait"
          [height, width + @layer_controls_height + extra_height,
           "0 0 #{fmt(height)} #{fmt(width + @layer_controls_height + extra_height)}"]
        else
          [width, height + @layer_controls_height + extra_height,
           "#{fmt(left)} #{fmt(top)} #{fmt(width)} #{fmt(height + @layer_controls_height + extra_height)}"]
        end
        svg = ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
               "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"#{fmt(output_width)}\" height=\"#{fmt(output_height)}\" viewBox=\"#{output_view_box}\" font-family=\"Helvetica, Arial, 'Noto Sans JP', sans-serif\" fill=\"#{@colors[:text]}\" role=\"img\"#{@rail_pattern ? " data-rail-pattern=\"#{@rail_pattern}\"" : ""}>",
               "<title>#{escape(circuit.title || "Breadkit circuit")}</title>",
               "<desc>Breadboard wiring diagram generated by Breadkit.</desc>"]
        transform = if @orientation == "portrait"
          "matrix(0 1 -1 0 #{fmt(top + height)} #{fmt(-left + @layer_controls_height)})"
        elsif @layer_controls_height.positive?
          "translate(0 #{fmt(@layer_controls_height)})"
        end
        svg << "<g transform=\"#{transform}\">" if transform
        @rotated_scene = @orientation == "portrait"
        svg << "<g id=\"board\">#{board_svg}</g>"
        svg << "<g id=\"holes\">#{holes_svg}</g>"
        svg << "<g id=\"components\">#{components_svg}</g>"
        svg << "<g id=\"offboard\">#{offboard_svg}</g>"
        svg << "<g id=\"wires\">#{wires_svg}</g>"
        svg << "<g id=\"labels\">#{labels_svg}</g>"
        svg << "<g id=\"nets\">#{nets_svg}</g><g id=\"annotations\">#{annotations_svg}</g>"
        svg << "</g>" if transform
        @rotated_scene = false
        svg << "<g id=\"layer-controls\">#{layer_controls_svg}</g>" if @layer_controls_height.positive?
        svg << layer_controls_script if @layer_controls_height.positive?
        svg << "<g id=\"legend\">#{legend || !@annotations.empty? ? legend_svg : ""}</g></svg>"
        svg.join("\n")
      end

      private

      def configure_rail_pattern
        @rail_position_map = {}
        return unless @rail_pattern
        raise ArgumentError, "unsupported rail pattern: #{@rail_pattern}" unless RAIL_PATTERNS.include?(@rail_pattern)

        rails = @circuit.board.holes.values.select { |hole| hole.kind == :rail }.group_by(&:rail)
        positions = rails.map { |id, holes| [id, holes.sum(&:y) / holes.length] }
        pairs = %w[bottom top].map do |side|
          positions.select { |id, _y| rail_definition(id)["side"].to_s == side }.sort_by(&:last)
        end
        valid_pairs = pairs.all? do |pair|
          polarities = pair.map { |id, _y| rail_polarity(id) }
          pair.length == 2 && polarities.compact.length == 2 && polarities.sort == %w[+ -]
        end
        raise ArgumentError, "rail pattern requires two +/− rail pairs" unless positions.length == 4 && valid_pairs

        slots = pairs.flatten(1).map(&:first)
        @rail_pattern_slots = slots.zip(@rail_pattern.chars)
        polarity_by_rail = @rail_pattern_slots.to_h
        pairs.each do |pair|
          pair.each do |id, _y|
            polarity = rail_polarity(id)
            @rail_position_map[id] = pair.find { |rail_id, _rail_y| polarity_by_rail[rail_id] == polarity }.first
          end
        end
      end

      def rail_definition(id)
        @rail_definitions.fetch(id.to_s, {})
      end

      def rail_polarity(id)
        rail_definition(id)["polarity"]&.to_s || (id.end_with?("+", "-") ? id[-1] : nil)
      end

      def display_hole(hole)
        return hole unless @rail_pattern && hole&.kind == :rail

        rail_id = @rail_position_map.fetch(hole.rail, hole.rail)
        @circuit.board.hole("#{rail_id}#{hole.col}") || hole
      end

      def rail_marks_svg
        polarity_by_rail = @rail_pattern_slots.to_h
        @circuit.board.strips.values.filter_map do |ids|
          holes = ids.map { |id| @circuit.board.hole(id) }
          next unless holes.first&.kind == :rail

          hole = holes.min_by(&:x)
          polarity = polarity_by_rail.fetch(hole.rail)
          text(px(hole.x) - 5, py(hole.y) + 2, polarity, "font-size" => 7, "font-weight" => 700,
               "fill" => polarity == "+" ? @colors[:positive] : @colors[:negative], "text-anchor" => "middle",
               "data-rail" => hole.rail)
        end.join
      end

      def board_svg
        x, y, width, height = board_bounds
        out = [rect(x, y, width, height, rx: 8, fill: @colors[:board], stroke: @colors[:border], stroke_width: 1)]
        ravine = Array(@circuit.board.definition.data.dig("terminal", "ravine_between"))
        rows = ravine.map { |row| @circuit.board.holes.values.find { |hole| hole.row == row.to_s } }
        if rows.length == 2 && rows.all?
          groove_y = rows.sum { |hole| py(hole.y) } / rows.length
          groove_width = PITCH * 2
          out << rect(x + PITCH / 2, groove_y - groove_width / 2, width - PITCH, groove_width,
                      rx: 2, fill: @colors[:groove])
        end
        @circuit.board.strips.each do |id, ids|
          next unless id.start_with?("rail:")
          holes = ids.map { |hole_id| @circuit.board.hole(hole_id) }
          next if holes.empty?
          rail_id = holes.first.rail
          rail_color = { "+" => @colors[:positive], "-" => @colors[:negative] }.fetch(rail_polarity(rail_id), @colors[:label])
          positions = holes.map { |hole| display_hole(hole) }
          first, last = positions.map { |hole| px(hole.x) }.minmax
          out << rect(first - 3, py(positions.first.y) - 3, last - first + 6, 6,
                      rx: 3, fill: rail_color, opacity: 0.14, data_rail: rail_id)
        end
        out.join
      end

      def holes_svg
        @circuit.board.holes.values.map do |hole|
          used = @used_holes.include?(hole.id)
          connected = @conductive_holes.include?(hole.id)
          display = display_hole(hole)
          attrs = { fill: used ? @colors[:used_hole] : (connected ? @colors[:connected_hole] : @colors[:hole]),
                    data_hole: hole.id, opacity: used ? 1 : 0.75 }
          attrs[:data_occupied] = true if used
          attrs[:data_connected] = true if connected
          circle(px(display.x), py(display.y), used ? 1.8 : 1.3, **attrs)
        end.join
      end

      def labels_svg
        out = []
        number_y = @orientation == "portrait" ? py(-1) : py(@circuit.board.height)
        @circuit.board.definition.data.dig("terminal", "rows").each do |row|
          y = @circuit.board.holes.values.find { |hole| hole.row == row }&.y
          out << text(-7, py(y), row, "font-size" => 8, "font-weight" => 500, "fill" => @colors[:label], "text-anchor" => "middle") if y
        end
        (1..@circuit.board.width).each do |col|
          next unless col == 1 || (col % 5).zero?
          number_x = px(col - 1) + (@orientation == "portrait" ? 5 : 0)
          out << rect(number_x - 3, number_y - 5, 6, 10, rx: 2,
                      fill: @colors[:board], stroke: @colors[:border], stroke_width: 0.6) if @orientation == "portrait"
          out << text(number_x + (@orientation == "portrait" ? 3 : 0), number_y, col,
                      "font-size" => @orientation == "portrait" ? 6 : 7, "font-weight" => 500,
                      "fill" => @colors[:text], "text-anchor" => "middle")
        end
        out << rail_marks_svg if @rail_pattern
        out.join
      end

      def components_svg
        @circuit.components.values.map do |component|
          pins = component.pins.values.filter_map { |pin| [pin, @circuit.board.hole(pin.hole_id)] if pin.hole_id }
          next if pins.empty?
          xs, ys = pins.map { |_pin, hole| px(display_hole(hole).x) }, pins.map { |_pin, hole| py(display_hole(hole).y) }
          center_x, center_y = (xs.min + xs.max) / 2.0, (ys.min + ys.max) / 2.0
          shape = component.part.data.dig("render", "shape")
          body = case shape
          when "resistor" then resistor_svg(component, pins, center_x, center_y)
          when "led_5mm" then led_svg(component, pins, center_x, center_y)
          when "diode" then diode_svg(component, pins, center_x, center_y)
          when "capacitor", "electrolytic" then capacitor_svg(component, pins, center_x, center_y, electrolytic: shape == "electrolytic")
          when "dip" then dip_svg(component, pins)
          when "module" then module_svg(component, pins)
          when "tact_switch" then switch_svg(component, pins, center_x, center_y)
          else generic_svg(component, pins, center_x, center_y)
          end
          body = "<g data-ref=\"#{escape(component.ref)}\">#{body}</g>"
          layer_group(body, read(component.attrs, "layer"))
        end.compact.join
      end

      def resistor_svg(component, pins, x, y)
        out = [lead_lines(pins, x, y)]
        out << rect(x - 12, y - 4, 24, 8, rx: 3, fill: @colors[:resistor_bg], stroke: @colors[:resistor_border], data_ref: component.ref)
        bands = resistor_bands(component.value, bands: component.attrs[:bands] || 4)
        bands.each_with_index { |color, index| out << rect(x - (bands.length == 5 ? 9 : 7) + index * 4, y - 4, 1.7, 8, fill: color) }
        out << text(x, y - 7, "#{component.ref} #{component.value}", "font-size" => 5, "font-weight" => 500, "text-anchor" => "middle")
        out.join
      end

      def led_svg(component, pins, x, y)
        out = [lead_lines(pins, x, y)]
        color = component.attrs[:color].to_s.downcase
        color = "red" if color.empty?
        valid_color = CSS_COLOR_NAMES.include?(color) || /\A#(?:[0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})\z/.match?(color)
        raise Error, "invalid LED color: #{color}" unless valid_color
        color = { "red" => "#df5550", "green" => "#5fbf69", "blue" => "#6a9df0", "yellow" => "#f0d958" }.fetch(color, color)
        out << circle(x, y, 5.5, fill: color, stroke: @colors[:component_border], data_ref: component.ref)
        out << polarity_marker(component, pins, x, y, 5.0, @colors[:component_border])
        out << text(x, y - 8, component.ref, "font-size" => 5, "font-weight" => 500, "text-anchor" => "middle")
        out.join
      end

      def diode_svg(component, pins, x, y)
        [lead_lines(pins, x, y), rect(x - 7, y - 3, 14, 6, rx: 1, fill: @colors[:diode_bg], stroke: @colors[:diode_border], data_ref: component.ref),
         polarity_marker(component, pins, x, y, 3.0, @colors[:diode_mark]),
         text(x, y - 5, component.ref, "font-size" => 4.5, "font-weight" => 500, "text-anchor" => "middle")].join
      end

      def capacitor_svg(component, pins, x, y, electrolytic:)
        out = [lead_lines(pins, x, y)]
        out << line(x - 2, y - 4, x - 2, y + 4, @colors[:lead], 1.1)
        out << line(x + 2, y - 4, x + 2, y + 4, @colors[:lead], 1.1)
        if electrolytic
          positive, negative = polarity_points(component, pins)
          offset_x = positive && negative && (positive[0] - negative[0]).abs < (positive[1] - negative[1]).abs ? 0 : (positive && positive[0] > x ? 5 : -5)
          offset_y = offset_x.zero? ? (positive && positive[1] > y ? 5 : -5) : 0
          out << text(x + offset_x, y + offset_y + 1.5, "+", "font-size" => 4, "text-anchor" => "middle")
        end
        out << text(x, y - 6, component.ref, "font-size" => 4.5, "font-weight" => 500, "text-anchor" => "middle")
        out.join
      end

      def dip_svg(component, pins)
        xs, ys = pins.map { |_pin, hole| px(display_hole(hole).x) }, pins.map { |_pin, hole| py(display_hole(hole).y) }
        x1, x2, middle = xs.min - 4, xs.max + 4, (ys.min + ys.max) / 2.0
        out = [rect(x1, middle - 4, x2 - x1, 8, rx: 2, fill: @colors[:dip_bg], stroke: @colors[:dip_border], data_ref: component.ref)]
        first_pin = pins.find { |pin, _hole| pin.number == "1" }&.last
        notch_x = first_pin && px(first_pin.x) > xs.sum / xs.length ? x2 - 2 : x1 + 2
        out << tag("path", d: "M #{fmt(notch_x)} #{fmt(middle - 2)} Q #{fmt(notch_x + (notch_x == x1 + 2 ? 2 : -2))} #{fmt(middle)} #{fmt(notch_x)} #{fmt(middle + 2)}",
                    fill: "none", stroke: @colors[:dip_notch], stroke_width: 0.8)
        out << text((x1 + x2) / 2, middle + 1.5, component.part.data.dig("render", "label") || component.ref,
                    "font-size" => 4.5, "fill" => @colors[:dip_text], "text-anchor" => "middle")
        pins.each do |pin, hole|
          display = display_hole(hole)
          out << text(px(display.x), py(display.y) + (display.y > 4 ? 4 : -2), pin.number, "font-size" => 3.5, "text-anchor" => "middle")
        end
        out.join
      end

      def module_svg(component, pins)
        x, y, width, height = module_bounds(component, pins)
        x, y, width, height = px(x), py(y + height), px(width), px(height)
        center_x, center_y = x + width / 2, y + height / 2
        render = component.part.data.fetch("render")
        out = [rect(x, y, width, height, rx: 4, fill: render["fill"] || @colors[:module_bg],
                    stroke: render["stroke"] || @colors[:module_border], stroke_width: 1,
                    data_ref: component.ref)]
        pin_definitions = component.part.data["pins"].to_h { |definition| [definition["num"].to_s, definition] }
        pins.each do |pin, hole|
          display = display_hole(hole)
          pin_x, pin_y = px(display.x), py(display.y)
          definition = pin_definitions[pin.number]
          unused = component.unused.include?(pin.name) || component.unused.include?(pin.number)
          pin_color = unused ? @colors[:muted] : MODULE_PIN_COLORS.fetch(pin.role.to_s, "#d7bd79")
          out << circle(pin_x, pin_y, 2.3, fill: pin_color, stroke: render["stroke"] || @colors[:module_border], stroke_width: 0.7,
                        data_pin: "#{component.ref}.#{pin.name}")
          out << circle(pin_x, pin_y, 0.8, fill: render["stroke"] || @colors[:module_border])
          label = definition && definition["label"]
          next unless label
          label = pin.name if label == true
          label_gap = @orientation == "portrait" ? 10 : 3.8
          label_y = pin_y + (center_y > pin_y ? label_gap : -label_gap)
          label_anchor = @orientation == "portrait" ? (center_y > pin_y ? "end" : "start") : "middle"
          out << text(pin_x, label_y, label, "font-size" => 5.8, "font-weight" => 500,
                      "fill" => render["text_color"] || @colors[:text], "text-anchor" => label_anchor)
        end
        label = render["label"] || component.ref
        font_size = [[ [width, height].min / 6, 6].max, 10].min
        label_units = label.to_s.each_char.sum { |char| char.ascii_only? ? 0.6 : 1.0 }
        label_space = @orientation == "portrait" ? height : width
        font_size = [font_size, (label_space - 4) / label_units].min if label_units.positive? && label_space > 4
        label_x, label_y = center_x, center_y + (@orientation == "portrait" ? 0 : font_size / 3)
        label_width = label_units * font_size
        half_width, half_height = @orientation == "portrait" ? [font_size / 2, label_width / 2] : [label_width / 2, font_size / 2]
        if pins.any? { |_pin, hole| (px(display_hole(hole).x) - label_x).abs < half_width + 2.3 &&
                                    (py(display_hole(hole).y) - label_y).abs < half_height + 2.3 }
          label_x = x + width - font_size - 1 if @orientation == "portrait"
          label_y = y + height - font_size - 1 if @orientation == "landscape"
        end
        out << text(label_x, label_y, label, "font-size" => font_size,
                    "font-weight" => 600, "fill" => render["text_color"] || @colors[:text], "text-anchor" => "middle")
        out.join
      end

      def module_bounds(component, pins)
        xs, ys = pins.map { |_pin, hole| hole.x }, pins.map { |_pin, hole| hole.y }
        render = component.part.data.fetch("render")
        width_mm, height_mm = render.fetch("size_mm").map { |value| Float(value) }
        offset_x, offset_y = Array(render["body_offset_mm"]).map { |value| Float(value) / 2.54 }
        offset_x ||= 0
        offset_y ||= 0
        width, height = width_mm / 2.54, height_mm / 2.54
        center_x, center_y = (xs.min + xs.max) / 2.0 + offset_x, (ys.min + ys.max) / 2.0 + offset_y
        [center_x - width / 2, center_y - height / 2, width, height]
      end

      def switch_svg(component, pins, x, y)
        out = [lead_lines(pins, x, y)]
        out << rect(x - 12, y - 10, 24, 20, rx: 2, fill: @colors[:switch_bg], stroke: @colors[:switch_border], data_ref: component.ref)
        out << circle(x, y, 5, fill: @colors[:switch_button], stroke: @colors[:switch_button_border])
        out << text(x, y - 13, component.ref, "font-size" => 5, "font-weight" => 500, "text-anchor" => "middle")
        out.join
      end

      def generic_svg(component, pins, x, y)
        out = [lead_lines(pins, x, y)]
        out << rect(x - 9, y - 5, 18, 10, rx: 2, fill: @colors[:component_bg], stroke: @colors[:component_border], data_ref: component.ref)
        out << text(x, y + 1.5, component.ref, "font-size" => 4.5, "font-weight" => 500, "text-anchor" => "middle")
        out.join
      end

      def offboard_svg
        @circuit.components.values.filter_map do |component|
          next unless component.part.placement == "offboard"
          pins = component.pins.values
          x, y, width, height, _pin_edge = offboard_layout(component)
          out = [rect(px(x), py(y + height), px(width), px(height), rx: 2,
                      fill: @colors[:module_bg], stroke: @colors[:module_border], data_ref: component.ref)]
          label = component.attrs[:label] || component.part.data.dig("render", "label") || component.ref
          if @orientation == "portrait"
            label_x, label_y = px(x + width / 2 - 0.45), py(y + height / 2)
            out << text(label_x, label_y, label, "font-size" => 6.5, "font-weight" => 600,
                        "text-anchor" => "middle", "fill" => @colors[:text])
            out << text(label_x + px(0.9), label_y, component.attrs[:address], "font-size" => 5.2,
                        "text-anchor" => "middle", "fill" => @colors[:label]) if component.attrs[:address]
          else
            label_x, label_y = px(x + width / 2), py(y + height / 2)
            out << text(label_x, label_y - 3, label, "font-size" => 6.5, "font-weight" => 600,
                        "text-anchor" => "middle", "fill" => @colors[:text])
            out << text(label_x, label_y + 5, component.attrs[:address], "font-size" => 5.2,
                        "text-anchor" => "middle", "fill" => @colors[:label]) if component.attrs[:address]
          end
          pins.each_with_index do |pin, index|
            pin_x, pin_y = offboard_pin_point(component, index)
            pin_color = MODULE_PIN_COLORS.fetch(pin.role.to_s, @colors[:lead])
            out << circle(px(pin_x), py(pin_y), 1.7, fill: pin_color, stroke: @colors[:module_bg],
                          stroke_width: 0.6, data_pin: "#{component.ref}.#{pin.name}", data_pin_type: pin.role)
            references = ["#{component.ref}.#{pin.name}", "#{component.ref}.#{pin.number}"]
            connected = references.any? { |reference| @wire_endpoint_refs.key?(reference) }
            label_side = component.attrs[:side].to_s == "left"
            label_x = if @orientation == "portrait"
              px(pin_x)
            else
              px(pin_x + (label_side ? -0.8 : 0.8))
            end
            label_y = @orientation == "portrait" ? py(pin_y) + (label_side ? 5.5 : -4.5) : py(pin_y) + 1
            anchor = if @orientation == "portrait"
              label_side ? "end" : "start"
            else
              label_side ? "end" : "start"
            end
            out << text(label_x, label_y, pin.name, "font-size" => 5.4, "fill" => connected ? @colors[:text] : @colors[:muted],
                        "text-anchor" => anchor, data_pin_label: "#{component.ref}.#{pin.name}")
          end
          layer_group(out.join, read(component.attrs, "layer"))
        end.join
      end

      def lead_lines(pins, x, y)
        pins.map { |_pin, hole| display = display_hole(hole); line(px(display.x), py(display.y), x, y, @colors[:lead], 0.9) }.join
      end

      def polarity_points(component, pins)
        polarity = component.part.data["polarity"] || {}
        [polarity["positive"], polarity["negative"]].map do |name|
          pin, hole = pins.find { |candidate, _hole| candidate.name == name }
          display = display_hole(hole)
          [px(display.x), py(display.y)] if pin && hole
        end
      end

      def polarity_marker(component, pins, x, y, extent, color)
        positive, negative = polarity_points(component, pins)
        if positive && negative && (negative[0] - positive[0]).abs >= (negative[1] - positive[1]).abs
          marker_x = negative[0] > positive[0] ? x + extent / 2 : x - extent / 2
          line(marker_x, y - extent, marker_x, y + extent, color, 1.2)
        elsif positive && negative
          marker_y = negative[1] > positive[1] ? y + extent / 2 : y - extent / 2
          line(x - extent, marker_y, x + extent, marker_y, color, 1.2)
        else
          line(x - extent / 2, y - extent, x - extent / 2, y + extent, color, 1.2)
        end
      end

      def wires_svg
        casings, lines, markers = [], [], []
        @circuit.wires.each do |wire|
          from, to = endpoint_point(wire.from), endpoint_point(wire.to)
          next unless from && to
          color = @theme == "print" ? "#222222" : (wire.color || wire_color(wire))
          path = if wire.route == "arc"
            control_y = (py(from[1]) + py(to[1])) / 2.0 - 8
            "M #{fmt(px(from[0]))} #{fmt(py(from[1]))} Q #{fmt((px(from[0]) + px(to[0])) / 2)} #{fmt(control_y)} #{fmt(px(to[0]))} #{fmt(py(to[1]))}"
          elsif wire.route == "edge"
            edge_route(wire, from, to)
          else
            "M #{fmt(px(from[0]))} #{fmt(py(from[1]))} L #{fmt(px(to[0]))} #{fmt(py(to[1]))}"
          end
          dash = if wire.dashed
            " stroke-dasharray=\"5 4\""
          elsif @theme == "print"
            " stroke-dasharray=\"#{["8 3", "3 3", "1 3"][@wire_indexes.fetch(wire) % 3]}\""
          else
            ""
          end
          casing = "<path d=\"#{path}\" fill=\"none\" stroke=\"#{@colors[:board]}\" stroke-width=\"3.6\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>"
          wire_svg = "<path d=\"#{path}\" fill=\"none\" stroke=\"#{escape(color)}\" stroke-width=\"2.4\" stroke-linecap=\"round\" stroke-linejoin=\"round\" data-ref=\"#{escape(wire.id)}\"#{dash}/>"
          dots = [from, to].uniq.map do |x, y|
            circle(px(x), py(y), 2.8, fill: color, stroke: @colors[:board], stroke_width: 1.2,
                   data_wire: wire.id)
          end
          alternative = wire.electrical == false
          casings << layer_group(casing, wire.layer, alternative: alternative)
          lines << layer_group(wire_svg, wire.layer, alternative: alternative)
          markers << layer_group(dots.join, wire.layer, alternative: alternative)
        end
        (casings + lines + markers).join
      end

      def layer_names(value)
        Array(value).filter_map { |name| name.to_s unless name.nil? || name.to_s.empty? }
      end

      def layer_group(content, names, alternative: false)
        names = layer_names(names)
        return content if names.empty?

        attributes = "data-layers=\"#{escape(JSON.generate(names))}\""
        attributes += " data-alternative=\"true\" opacity=\"0\"" if alternative
        "<g #{attributes}>#{content}</g>"
      end

      def layer_controls_height
        rows = layer_control_rows.length
        rows * 21.0 + 4
      end

      def layer_control_rows
        items = [["All", "*"]] + @layers.map { |name| [name, name] }
        available = (@orientation == "portrait" ? @view_box[3] : @view_box[2]) - 10
        rows = [[]]
        row_width = 0.0
        items.each do |label, value|
          width = layer_button_width(label)
          if row_width.positive? && row_width + width > available
            rows << []
            row_width = 0
          end
          rows.last << [label, value, width]
          row_width += width + 2
        end
        rows
      end

      def layer_button_width(label)
        label.each_char.sum { |char| char.match?(/[\p{Han}\p{Hiragana}\p{Katakana}]/) ? 9.5 : 6.5 } + 14
      end

      def layer_controls_svg
        x = @orientation == "portrait" ? 5.0 : @view_box[0] + 5.0
        y = @orientation == "portrait" ? 3.0 : @view_box[1] + 3.0
        out = ["<style>g[data-layer-button]{cursor:pointer}g[data-layer-button]:focus rect{stroke-width:2.5}</style>"]
        layer_control_rows.each_with_index do |row, row_index|
          row_x = x
          row.each do |label, value, width|
            button_y = y + row_index * 21.0
            active = value == "*"
            out << "<g data-layer-button=\"#{escape(value)}\" role=\"button\" tabindex=\"0\" aria-label=\"#{escape(label)}\" aria-pressed=\"#{active}\" cursor=\"pointer\">"
            out << "<title>#{escape(label)}</title>"
            out << rect(row_x, button_y, width, 18, rx: 9,
                        fill: active ? @colors[:component_bg] : @colors[:board],
                        stroke: active ? @colors[:accent] : @colors[:component_border], stroke_width: active ? 1.2 : 0.7)
            out << text(row_x + width / 2, button_y + 12.2, label, "font-size" => 9,
                        "font-weight" => active ? 600 : 400,
                        "fill" => active ? @colors[:accent] : @colors[:text], "text-anchor" => "middle")
            out << "</g>"
            row_x += width + 2
          end
        end
        out.join
      end

      def layer_controls_script
        <<~SVG
          <script><![CDATA[
            (function () {
              var svg = document.currentScript.parentElement;
              var buttons = svg.querySelectorAll("[data-layer-button]");
              function selectLayer(selected) {
                svg.querySelectorAll("[data-layers]").forEach(function (item) {
                  var matches = JSON.parse(item.getAttribute("data-layers")).includes(selected);
                  var opacity = selected === "*" ? (item.getAttribute("data-alternative") === "true" ? "0" : "1") :
                    (matches ? "1" : (item.getAttribute("data-alternative") === "true" ? "0" : "0.12"));
                  item.setAttribute("opacity", opacity);
                });
                buttons.forEach(function (button) {
                  var active = button.getAttribute("data-layer-button") === selected;
                  button.setAttribute("aria-pressed", active ? "true" : "false");
                  button.querySelector("rect").setAttribute("stroke", active ? "#{@colors[:accent]}" : "#{@colors[:component_border]}");
                  button.querySelector("rect").setAttribute("fill", active ? "#{@colors[:component_bg]}" : "#{@colors[:board]}");
                  button.querySelector("text").setAttribute("fill", active ? "#{@colors[:accent]}" : "#{@colors[:text]}");
                  button.querySelector("text").setAttribute("font-weight", active ? "600" : "400");
                });
              }
              buttons.forEach(function (button) {
                var activate = function () { selectLayer(button.getAttribute("data-layer-button")); };
                button.addEventListener("click", activate);
                button.addEventListener("keydown", function (event) {
                  if (event.key === "Enter" || event.key === " ") { event.preventDefault(); activate(); }
                });
              });
            })();
          ]]></script>
        SVG
      end

      def nets_svg
        return "" unless @show_nets
        @circuit.nets.map do |net|
          hole = @circuit.board.hole(net.holes.first)
          next unless hole
          display = display_hole(hole)
          text(px(display.x) + 5, py(display.y) - 5, net.name, "font-size" => 5, "font-weight" => 500,
               "fill" => @colors[:text], "data-net" => net.name)
        end.compact.join
      end

      def legend_svg
        return "" unless @legend_enabled || !@annotations.empty?

        x = @orientation == "portrait" ? 5 : @view_box[0] + 5
        y = @orientation == "portrait" ? @view_box[2] + @layer_controls_height + 9 : @view_box[1] + @view_box[3] + @layer_controls_height + 9
        panel_x = @orientation == "portrait" ? 0 : @view_box[0]
        panel_y = y - 9
        panel_width = @orientation == "portrait" ? @view_box[3] : @view_box[2]
        out = [rect(panel_x, panel_y, panel_width, legend_height, fill: @colors[:board]),
               text(x, y, @circuit.title || "Breadkit circuit", "font-size" => 8, "font-weight" => "bold")]
        y += 11
        if @legend_enabled
          legend_nets.each do |net|
            out << line(x, y - 1.5, x + 10, y - 1.5, legend_color(net), 2.2)
            out << text(x + 15, y, net.name, "font-size" => 5.5)
            y += 9
          end
        end
        @annotations.each_with_index do |item, index|
          message = read(item, "message") || read(item, "rule")
          annotation_lines("#{index + 1}. #{message}").each do |line|
            out << text(x, y, line, "font-size" => 5)
            y += 7
          end
          y += 2
        end
        out.join
      end

      def legend_color(net)
        return "#222222" if @theme == "print"

        wire = net.members.filter_map { |member| @wires_by_id[member] }.first
        wire ? (wire.color || wire_color(wire)) : PALETTE[@net_indexes.fetch(net) % PALETTE.length]
      end

      def legend_nets
        @circuit.nets.reject { |net| net.members.length == 1 && net.holes.empty? }
      end

      def annotations_svg
        badge_counts = Hash.new(0)
        @annotations.each_with_index.map do |item, index|
          targets = read(item, "targets") || {}
          severity = read(item, "severity")
          color = { "error" => "#d62728", "warning" => "#e67e22", "info" => "#2474c2" }.fetch(severity, "#d62728")
          out = []
          anchor = nil
          Array(read(targets, "holes")).each do |id|
            hole = @circuit.board.hole(id)
            if hole
              display = display_hole(hole)
              x, y = px(display.x), py(display.y)
              anchor ||= [x, y]
              out << circle(x, y, 4, fill: "none", stroke: color, stroke_width: 1.5)
            end
          end
          Array(read(targets, "wires")).each do |id|
            wire = @wires_by_id[id]
            next unless wire
            point = endpoint_point(wire.from)
            if point
              x, y = px(point[0]), py(point[1])
              anchor ||= [x, y]
              out << circle(x, y, 5, fill: "none", stroke: color, stroke_width: 1.5)
            end
          end
          Array(read(targets, "components")).each do |ref|
            component = @circuit.components[ref]
            holes = component && component.pins.values.map { |pin| @circuit.board.hole(pin.hole_id) }.compact
            next if holes.nil? || holes.empty?
            xs, ys = holes.map { |hole| px(display_hole(hole).x) }, holes.map { |hole| py(display_hole(hole).y) }
            anchor ||= [(xs.min + xs.max) / 2, (ys.min + ys.max) / 2]
            out << rect(xs.min - 7, ys.min - 7, xs.max - xs.min + 14, ys.max - ys.min + 14,
                        fill: "none", stroke: color, stroke_width: 1.5)
          end
          Array(read(targets, "nets")).each do |name|
            state_name = read(item, "state")
            if state_name
              @annotation_states ||= @circuit.states("all").to_h { |candidate| [candidate.name, candidate] }
              state = @annotation_states[state_name]
              next unless state
            end
            net = @circuit.nets(state).find { |candidate| candidate.name == name }
            next unless net
            if net.holes.empty?
              point = net.members.filter_map { |member| endpoint_point(member) }.first
              if point
                x, y = px(point[0]), py(point[1])
                anchor ||= [x, y]
                out << circle(x, y, 4, fill: "none", stroke: color, stroke_width: 1.5)
              end
            end
            net.holes.each do |id|
              hole = @circuit.board.hole(id)
              next unless hole
              display = display_hole(hole)
              x, y = px(display.x), py(display.y)
              anchor ||= [x, y]
              out << circle(x, y, 3, fill: "none", stroke: color, stroke_width: 1)
            end
          end
          if anchor
            x, y = anchor
            key = [x.round, y.round]
            badge_x = x + 7 + badge_counts[key] * 11
            badge_counts[key] += 1
            out << circle(badge_x, y - 7, 5, fill: color, stroke: @colors[:board], stroke_width: 0.8)
            out << text(badge_x, y - 5.5, index + 1, "font-size" => 5, "font-weight" => "bold",
                        "fill" => "#ffffff", "text-anchor" => "middle")
          end
          out.join
        end.join
      end

      def annotation_lines(message)
        max_width = (@orientation == "portrait" ? @view_box[3] : @view_box[2]) - 20
        lines, line, width = [], +"", 0
        message.each_grapheme_cluster do |char|
          if char == "\n"
            lines << line
            line, width = +"", 0
            next
          end
          char_width = if char.match?(/[\u{1F000}-\u{1FAFF}]/)
            10
          elsif !char.ascii_only?
            6
          elsif char.match?(/[MW@%]/)
            5
          else
            4
          end
          if width + char_width > max_width && !line.empty?
            lines << line
            line, width = +"", 0
          end
          line << char
          width += char_width
        end
        lines << line unless line.empty?
        lines
      end

      def read(hash, key)
        hash[key] || hash[key.to_sym] if hash.respond_to?(:[])
      end

      def view_box(mode)
        offboard = @circuit.components.values.any? { |component| component.part.placement == "offboard" }
        wire_points = @circuit.wires.flat_map do |wire|
          from, to = endpoint_point(wire.from), endpoint_point(wire.to)
          from && to ? wire_route_points(wire, from, to) : []
        end
        if mode == "none" || (@used_holes.empty? && !offboard)
          left, top, width, height = board_bounds
          module_points = wire_points + @circuit.components.values.flat_map do |component|
            if component.part.placement == "offboard"
              offboard_bounds(component)
            elsif component.part.data.dig("render", "shape") == "module"
              pins = component.pins.values.filter_map { |pin| [pin, @circuit.board.hole(pin.hole_id)] if pin.hole_id }
              next [] if pins.empty?
              x, y, module_width, module_height = module_bounds(component, pins)
              [[x, y], [x + module_width, y + module_height]]
            else
              []
            end
          end
          unless module_points.empty?
            xs = module_points.map { |x, _y| px(x) }
            ys = module_points.map { |_x, y| py(y) }
            right = [left + width, xs.max].max
            bottom = [top + height, ys.max].max
            left = [left, xs.min].min
            top = [top, ys.min].min
            width, height = right - left, bottom - top
          end
          return [left - PITCH, top - PITCH, width + PITCH * 2, height + PITCH * 2]
        end
        points = @used_holes.filter_map do |id|
          hole = @circuit.board.hole(id)
          display = display_hole(hole) if hole
          [display.x, display.y] if display
        end
        points.concat(wire_points)
        points.concat(@circuit.components.values.select { |component| component.part.placement == "offboard" }
                              .flat_map { |component| offboard_bounds(component) })
        points.concat(@circuit.components.values.flat_map do |component|
          next [] unless component.part.data.dig("render", "shape") == "module"
          pins = component.pins.values.filter_map { |pin| [pin, @circuit.board.hole(pin.hole_id)] if pin.hole_id }
          next [] if pins.empty?
          x, y, width, height = module_bounds(component, pins)
          [[x, y], [x + width, y + height]]
        end)
        xs, ys = points.map { |x, _y| px(x) }, points.map { |_x, y| py(y) }
        return board_bounds if xs.empty?
        [xs.min - 25, ys.min - 30, [xs.max - xs.min + 50, 100].max, [ys.max - ys.min + 65, 100].max]
      end

      def legend_height
        return 0 unless @legend_enabled || !@annotations.empty?

        20 + (@legend_enabled ? legend_nets.length * 9 : 0) +
          @annotations.each_with_index.sum { |item, index| annotation_lines("#{index + 1}. #{read(item, "message") || read(item, "rule")}").length * 7 + 2 }
      end

      def board_bounds
        points = @circuit.board.holes.values
        xs = points.map { |hole| px(hole.x) }
        ys = points.map { |hole| py(hole.y) }
        margin = PITCH * 1.5
        [xs.min - margin, ys.min - margin, xs.max - xs.min + margin * 2, ys.max - ys.min + margin * 2]
      end

      def endpoint_point(endpoint)
        parsed = Breadkit::HoleId.parse(endpoint, board: @circuit.board)
        if parsed.kind == :pin
          component = @circuit.components[parsed.ref]
          if component&.part&.placement == "offboard"
            pins = component.pins.values
            pin = pins.find { |item| item.name == parsed.pin || item.number == parsed.pin }
            return unless pin
            return offboard_pin_point(component, pins.index(pin))
          end
        end
        hole = @circuit.board.hole(endpoint)
        display = display_hole(hole) if hole
        [display.x, display.y] if display
      rescue ArgumentError
        nil
      end

      def edge_route(wire, from, to)
        points = edge_route_points(wire, from, to)
        "M #{points.map { |x, y| "#{fmt(px(x))} #{fmt(py(y))}" }.join(' L ')}"
      end

      def wire_route_points(wire, from, to)
        if wire.route == "edge"
          edge_route_points(wire, from, to)
        elsif wire.route == "arc"
          [from, [(from[0] + to[0]) / 2.0, (from[1] + to[1]) / 2.0 + 0.8], to]
        else
          [from, to]
        end
      end

      def edge_route_points(wire, from, to)
        module_from = offboard_component(wire.from)
        module_to = offboard_component(wire.to)
        if module_from || module_to
          module_point, board_point = module_from ? [from, to] : [to, from]
          board_endpoint = module_from ? wire.to : wire.from
          hole = @circuit.board.hole(board_endpoint)
          if hole&.kind == :terminal
            component = module_from || module_to
            side = component.attrs[:side].to_s == "left" ? "left" : "right"
            @offboard_terminal_indexes[side] ||= offboard_terminal_wires(side).each_with_index.to_h
            index = @offboard_terminal_indexes.fetch(side).fetch(wire)
            axis = @orientation == "portrait" ? :y : :x
            minimum, maximum = @board_extents.fetch(axis)
            lane = (side == "right" ? maximum : minimum) + (side == "right" ? 1 : -1) * (1.5 + index * 0.7)
            target_axis = @orientation == "portrait" ? 0 : 1
            @offboard_terminal_breakouts[side] ||= begin
              groups = offboard_terminal_wires(side).group_by do |item|
                endpoint = offboard_component(item.from) ? item.to : item.from
                endpoint_point(endpoint)&.[](target_axis)
              end
              groups.values.each_with_object({}) do |peers, offsets|
                peers.each_with_index { |item, position| offsets[item] = (position - (peers.length - 1) / 2.0) * 0.6 }
              end
            end
            breakout = @offboard_terminal_breakouts.fetch(side).fetch(wire)
            points = if @orientation == "portrait"
              x = board_point[0] + breakout
              [module_point, [module_point[0], lane], [x, lane], [x, board_point[1]], board_point]
            else
              y = board_point[1] + breakout
              [module_point, [lane, module_point[1]], [lane, y], [board_point[0], y], board_point]
            end
          elsif hole&.kind == :rail && @orientation == "portrait"
            component = module_from || module_to
            side = component.attrs[:side].to_s == "left" ? "left" : "right"
            track = offboard_rail_tracks(side, board_point[1]).fetch(wire, 0)
            outer = side == "right" ? @rail_y_extents.last : @rail_y_extents.first
            direction = board_point[1] == outer ? (side == "right" ? 1 : -1) : (side == "right" ? -1 : 1)
            lane = board_point[1] + direction * track * 0.7
            points = [module_point, [module_point[0], lane], [board_point[0], lane], board_point]
          else
            points = [module_point, [module_point[0], board_point[1]], board_point]
          end
          points.reverse! unless module_from
        else
          offset = (@board_edge_indexes.fetch(wire) - (@board_edge_wires.length - 1) / 2.0) * 0.8
          lane = from[1] <= @circuit.board.height / 2.0 ? -4.5 + offset : @circuit.board.height + 4.5 + offset
          from_offset = edge_breakout_offset(wire, from[0])
          to_offset = edge_breakout_offset(wire, to[0])
          points = [from]
          points << [from[0] + from_offset, from[1]] unless from_offset.zero?
          points.concat([[from[0] + from_offset, lane], [to[0] + to_offset, lane], [to[0] + to_offset, to[1]]])
          points << to unless to_offset.zero?
        end
        points
      end

      def edge_breakout_offset(wire, x)
        @edge_breakout_offsets ||= begin
          groups = Hash.new { |hash, key| hash[key] = [] }
          @board_edge_wires.each do |item|
            first, last = endpoint_point(item.from), endpoint_point(item.to)
            [first&.first, last&.first].compact.uniq.each { |position| groups[position] << item }
          end
          groups.transform_values do |peers|
            peers.each_with_index.to_h { |item, index| [item, (index - (peers.length - 1) / 2.0) * 0.4] }
          end
        end
        @edge_breakout_offsets.fetch(x, {}).fetch(wire, 0)
      end

      def offboard_terminal_wires(side)
        @offboard_terminal_wires[side] ||= @circuit.wires.select do |wire|
          next false unless wire.route == "edge"
          module_from = offboard_component(wire.from)
          module_to = offboard_component(wire.to)
          component = module_from || module_to
          next false unless component && (component.attrs[:side].to_s == "left" ? "left" : "right") == side
          @circuit.board.hole(module_from ? wire.to : wire.from)&.kind == :terminal
        end
      end

      def offboard_rail_tracks(side, target_y)
        @offboard_rail_tracks ||= begin
          groups = Hash.new { |hash, key| hash[key] = [] }
          @circuit.wires.each do |wire|
            next unless wire.route == "edge"
            module_from = offboard_component(wire.from)
            module_to = offboard_component(wire.to)
            component = module_from || module_to
            next unless component
            board_endpoint = module_from ? wire.to : wire.from
            next unless @circuit.board.hole(board_endpoint)&.kind == :rail
            from, to = endpoint_point(wire.from), endpoint_point(wire.to)
            next unless from && to
            wire_side = component.attrs[:side].to_s == "left" ? "left" : "right"
            y = (module_from ? to : from)[1]
            groups[[wire_side, y]] << [wire, [from[0], to[0]].minmax]
          end
          groups.transform_values do |items|
            assigned = {}
            active, free_tracks, next_track = [], [], 0
            items.sort_by { |wire, range| [range[0], @wire_indexes.fetch(wire)] }.each do |wire, range|
              while active.any? && active.first[0] < range[0]
                heap_push(free_tracks, [heap_pop(active)[1]])
              end
              track = if free_tracks.empty?
                next_track.tap { next_track += 1 }
              else
                heap_pop(free_tracks)[0]
              end
              heap_push(active, [range[1], track])
              assigned[wire] = track
            end
            assigned
          end
        end
        @offboard_rail_tracks.fetch([side, target_y], {})
      end

      def heap_push(heap, item)
        child = heap.length
        heap << item
        while child.positive?
          parent = (child - 1) / 2
          break if (heap[parent] <=> item) <= 0
          heap[child] = heap[parent]
          child = parent
        end
        heap[child] = item
      end

      def heap_pop(heap)
        first = heap.first
        last = heap.pop
        return first if heap.empty?

        parent = 0
        while (child = parent * 2 + 1) < heap.length
          child += 1 if child + 1 < heap.length && (heap[child + 1] <=> heap[child]).negative?
          break if (last <=> heap[child]) <= 0
          heap[parent] = heap[child]
          parent = child
        end
        heap[parent] = last
        first
      end

      def offboard_component(endpoint)
        parsed = Breadkit::HoleId.parse(endpoint, board: @circuit.board)
        component = @circuit.components[parsed.ref] if parsed.kind == :pin
        component if component&.part&.placement == "offboard"
      rescue ArgumentError
        nil
      end

      def offboard_bounds(component)
        x, y, width, height, = offboard_layout(component)
        [[x, y], [x + width, y + height]]
      end

      def offboard_layout(component)
        return @offboard_layouts[component] if @offboard_layouts.key?(component)

        side = component.attrs[:side].to_s == "left" ? "left" : "right"
        pins = component.pins.length
        height = [(pins - 1) * OFFBOARD_PIN_PITCH + 1.5, 4.0].max
        pin_span = [pins - 1, 0].max * OFFBOARD_PIN_PITCH
        margin = (height - pin_span) / 2.0
        row_anchor = component.attrs[:at]
        anchor = Breadkit::HoleId.parse(row_anchor, board: @circuit.board) if row_anchor
        start = anchor&.kind == :terminal ? anchor.col - 1 - margin : automatic_offboard_start(component)

        axis = @orientation == "portrait" ? :y : :x
        minimum, maximum = @board_extents.fetch(axis)
        depth = 7.0
        clearance = [6.0, 2.5 + [offboard_terminal_wires(side).length - 1, 0].max * 0.7].max
        position = side == "right" ? maximum + clearance : minimum - clearance - depth
        pin_edge = position + (side == "right" ? 0 : depth)

        @offboard_layouts[component] = @orientation == "portrait" ? [start, position, height, depth, pin_edge] :
          [position, start, depth, height, pin_edge]
      end

      def automatic_offboard_start(component)
        side = component.attrs[:side].to_s == "left" ? "left" : "right"
        peers = @circuit.components.values.select do |item|
          item.part.placement == "offboard" && item.attrs[:side].to_s == side
        end
        gap = 1.2
        total = peers.sum { |item| [(item.pins.length - 1) * OFFBOARD_PIN_PITCH + 1.5, 4.0].max } + gap * (peers.length - 1)
        cursor = ((@orientation == "portrait" ? @circuit.board.width : @circuit.board.height) - total) / 2.0
        peers.each do |item|
          item_height = [(item.pins.length - 1) * OFFBOARD_PIN_PITCH + 1.5, 4.0].max
          return cursor if item.equal?(component)
          cursor += item_height + gap
        end
        cursor
      end

      def offboard_pin_point(component, index)
        x, y, width, height, pin_edge = offboard_layout(component)
        pins = component.pins.length
        span = @orientation == "portrait" ? width : height
        margin = (span - [pins - 1, 0].max * OFFBOARD_PIN_PITCH) / 2.0
        position = x + margin + index * OFFBOARD_PIN_PITCH if @orientation == "portrait"
        position = y + margin + index * OFFBOARD_PIN_PITCH if @orientation == "landscape"
        @orientation == "portrait" ? [position, pin_edge] : [pin_edge, position]
      end

      def wire_color(wire)
        if @color_by == "net"
          net = @nets_by_member[wire.id] || @nets_by_hole[wire.from]
          voltage = net && @circuit.potentials.values[net.name]
          return voltage.positive? ? @colors[:positive] : (voltage.negative? ? @colors[:negative_wire] : @colors[:text]) if voltage
          if net
            hash = net.name.each_byte.reduce(2_166_136_261) { |value, byte| ((value ^ byte) * 16_777_619) & 0xffffffff }
            return PALETTE[hash % PALETTE.length]
          end
        end
        PALETTE[@wire_indexes.fetch(wire) % PALETTE.length]
      end

      def resistor_bands(value, bands: 4)
        raise Error, "resistor bands must be 4 or 5" unless [4, 5].include?(bands)

        number = begin
          Breadkit::Value.parse(value || 0)
        rescue ArgumentError
          return Array.new(bands - 1, "#a0522d") + ["#d4af37"]
        end
        return Array.new(bands - 1, "#a0522d") + ["#d4af37"] if number <= 0
        significant = bands - 2
        exponent = Math.log10(number).floor - significant + 1
        digits = (number / (10.0**exponent)).round
        if digits >= 10**significant
          digits /= 10
          exponent += 1
        end
        colors = %w[#000000 #8b4513 #ff0000 #ff8c00 #ffff00 #008000 #0000ff #800080 #808080 #ffffff]
        multiplier = exponent.negative? ? { -3 => "#ff69b4", -2 => "#c0c0c0", -1 => "#d4af37" }[exponent] : colors[exponent]
        raise Error, "resistor value is outside color-band range" unless multiplier

        digits.digits.reverse.map { |digit| colors[digit] }.then do |result|
          result.unshift(colors[0]) until result.length == significant
          result + [multiplier, bands == 5 ? "#8b4513" : "#d4af37"]
        end
      end

      def px(x)
        x.to_f * PITCH
      end

      def py(y)
        (@circuit.board.height - 1 - y.to_f) * PITCH
      end

      def fmt(value)
        format("%.2f", value.to_f)
      end

      def escape(value)
        CGI.escapeHTML(value.to_s)
      end

      def tag(name, attrs = nil, **options)
        attrs = (attrs || {}).merge(options)
        attributes = attrs.map { |key, value| "#{key.to_s.tr('_', '-')}=\"#{escape(value)}\"" }.join(" ")
        "<#{name} #{attributes}/>"
      end

      def rect(x, y, width, height, **attrs)
        tag("rect", { x: fmt(x), y: fmt(y), width: fmt(width), height: fmt(height) }.merge(attrs))
      end

      def circle(x, y, radius, **attrs)
        tag("circle", { cx: fmt(x), cy: fmt(y), r: fmt(radius) }.merge(attrs))
      end

      def line(x1, y1, x2, y2, color, width)
        tag("line", x1: fmt(x1), y1: fmt(y1), x2: fmt(x2), y2: fmt(y2), stroke: color, stroke_width: fmt(width))
      end

      def text(x, y, value, attrs = {})
        attrs = { "transform" => "rotate(-90 #{fmt(x)} #{fmt(y)})" }.merge(attrs) if @rotated_scene
        attributes = { x: fmt(x), y: fmt(y) }.merge(attrs).map { |key, item| "#{key.to_s.tr('_', '-')}=\"#{escape(item)}\"" }.join(" ")
        "<text #{attributes}>#{escape(value)}</text>"
      end
    end
  end
end
