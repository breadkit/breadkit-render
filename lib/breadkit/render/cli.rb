# frozen_string_literal: true

require "optparse"
require "cgi/escape"
require "find"

module Breadkit
  module Render
    class CLI
      def run(argv)
        original_args = argv.dup
        options = { scale: 2.0, theme: "light", orientation: "portrait", color_by: "wire", crop: "auto", backend: "auto", quality: 90,
                    view: "breadboard", label_density: "full", wire_routing: "declared", wire_style: "raised" }
        parser = OptionParser.new do |opts|
          opts.banner = "Usage: bkrender [options] INPUT"
          opts.on("-o", "--output PATH") { |value| options[:output] = value }
          opts.on("-f", "--format FORMAT", %w[svg html png jpeg jpg webp pdf apng]) { |value| options[:format] = value == "jpg" ? "jpeg" : value }
          opts.on("--view NAME", %w[breadboard netlist schematic]) { |value| options[:view] = value }
          opts.on("--scale N", Float) { |value| options[:scale] = value }
          opts.on("--theme NAME", %w[light dark print colorblind]) { |value| options[:theme] = value }
          opts.on("--theme-file PATH") { |value| options[:theme_file] = value }
          opts.on("--font-file PATH") { |value| options[:font_file] = value }
          opts.on("--orientation NAME", %w[portrait landscape]) { |value| options[:orientation] = value }
          opts.on("--rail-pattern PATTERN", SvgRenderer::RAIL_PATTERNS) { |value| options[:rail_pattern] = value }
          opts.on("--color-by MODE", %w[wire net]) { |value| options[:color_by] = value }
          opts.on("--label-density MODE", SvgRenderer::LABEL_DENSITIES) { |value| options[:label_density] = value }
          opts.on("--wire-routing MODE", %w[declared auto]) { |value| options[:wire_routing] = value }
          opts.on("--wire-style MODE", %w[raised flat]) { |value| options[:wire_style] = value }
          opts.on("--show-nets") { options[:show_nets] = true }
          opts.on("--legend") { options[:legend] = true }
          opts.on("--crop MODE", %w[auto none]) { |value| options[:crop] = value }
          opts.on("--annotations FILE") { |value| options[:annotations] = value }
          opts.on("--state NAME") { |value| options[:state] = value }
          opts.on("--step N", Integer) { |value| options[:step] = value }
          opts.on("--assembly-guide") { options[:assembly_guide] = true }
          opts.on("--animate MODE", %w[steps states]) { |value| options[:animate] = value }
          opts.on("--frame-delay MS", Integer) { |value| options[:frame_delay] = value }
          opts.on("--layer NAME") { |value| options[:layer] = value }
          opts.on("--focus REF") { |value| options[:focus] = value }
          opts.on("--highlight-net NAME") { |value| options[:highlight_net] = value }
          opts.on("--diff") { options[:diff] = true }
          opts.on("--backend NAME", %w[auto rsvg resvg vips magick chrome]) { |value| options[:backend] = value }
          opts.on("--background COLOR") { |value| options[:background] = value }
          opts.on("--static") { options[:static] = true }
          opts.on("--watch") { options[:watch] = true }
          opts.on("--quality N", Integer) { |value| options[:quality] = value }
          opts.on("--print-template") { options[:print_template] = true }
          opts.on("--render-timeout SECONDS", Float) { |value| options[:render_timeout] = value }
          opts.on("--force") { options[:force] = true }
          opts.on("-v", "--version") { puts "bkrender #{VERSION}"; return 0 }
          opts.on("-h", "--help") { puts opts; return 0 }
        end
        parser.parse!(argv)
        input = argv.shift
        raise ArgumentError, "input file required\n#{parser}" unless input
        second_input = argv.shift if options[:diff]
        raise ArgumentError, "--diff requires OLD and NEW inputs" if options[:diff] && !second_input
        raise ArgumentError, "unexpected arguments: #{argv.join(' ')}" unless argv.empty?
        format = output_format(options)
        if options[:assembly_guide]
          raise ArgumentError, "--assembly-guide requires HTML output" unless format == "html"
          raise ArgumentError, "--assembly-guide requires breadboard view" unless options[:view] == "breadboard"
          if options.values_at(:diff, :step, :state, :layer, :focus, :highlight_net, :annotations, :print_template).any?
            raise ArgumentError, "--assembly-guide cannot select a diff, step, state, layer, focus, annotations, or print template"
          end
        end
        if options[:theme_file]
          custom = Theme.load(options[:theme_file])
          options[:theme], options[:theme_colors] = custom.values_at(:base, :colors)
        end
        options[:font_css] = Theme.font(options[:font_file]) if options[:font_file]
        if options.values_at(:theme_file, :font_file).any? && options[:view] != "breadboard"
          raise ArgumentError, "custom themes and embedded fonts require breadboard view"
        end
        raise ArgumentError, "colorblind theme requires breadboard view" if options[:theme] == "colorblind" && options[:view] != "breadboard"
        raise ArgumentError, "--animate and --frame-delay require APNG output" if format != "apng" && options.values_at(:animate, :frame_delay).any?
        raise ArgumentError, "APNG cannot select a single --state or --step" if format == "apng" && options.values_at(:state, :step).any?
        validate_electrical_view_options(options, format) unless options[:view] == "breadboard"
        validate_step_options(options, format) if options[:step]
        if options[:print_template]
          raise ArgumentError, "--print-template requires PDF output" unless format == "pdf"
          options.merge!(theme: "print", crop: "none", scale: 1.0, static: true)
        end
        raise ArgumentError, "--background is only supported for JPEG" if options[:background] && format != "jpeg"
        raise ArgumentError, "cannot write binary image data to a terminal; use -o PATH" if !%w[svg html].include?(format) && !options[:output] && $stdout.tty?
        if options[:watch]
          raise ArgumentError, "--watch requires -o PATH" unless options[:output]
          original_args.delete_at(original_args.index("--watch"))
          return watch(input, second_input, options[:annotations], options[:output], original_args)
        end
        return render_diff(input, second_input, options, format) if options[:diff]
        circuit = Breadkit.load(input)
        circuit.diagnostics.each do |item|
          location = [item.location&.path, item.location&.line].compact.join(":")
          warn [location, item.severity || "error", item.message].reject { |value| value.nil? || value.empty? }.join(": ")
        end
        errors = circuit.diagnostics.reject { |item| %w[warning info].include?(item.severity) }
        return 1 if !errors.empty? && !options[:force]
        all_steps = circuit.respond_to?(:steps) ? circuit.steps : []
        step = select_step(all_steps, options[:step]) if options[:step]
        circuit = circuit_for_step(circuit, options[:step]) if step
        state = StateSelection.resolve(circuit, options[:state]) if options[:state]
        raise ArgumentError, "unknown circuit state: #{options[:state]}" if options[:state] && !state
        render_options = if %w[netlist schematic].include?(options[:view])
          { theme: options[:theme], state: state }
        else
          { crop: step ? "none" : options[:crop], theme: options[:theme], orientation: options[:orientation],
            show_nets: options[:show_nets], legend: options[:legend], color_by: options[:color_by],
            annotations: read_annotations(options[:annotations], input), rail_pattern: options[:rail_pattern],
            interactive_layers: !step && %w[svg html].include?(format) && !options[:static] && !options[:layer],
            state: state, active_layer: options[:layer], focus: options[:focus],
            highlight_net: options[:highlight_net], label_density: options[:label_density],
            theme_colors: options[:theme_colors] || {}, font_css: options[:font_css],
            wire_routing: options[:wire_routing], wire_style: options[:wire_style] }
        end
        renderer = { "breadboard" => SvgRenderer, "netlist" => NetlistRenderer,
                     "schematic" => SchematicRenderer }.fetch(options[:view])
        if options[:assembly_guide]
          output = assembly_guide(circuit, render_options, options[:theme])
          options[:output] ? File.binwrite(options[:output], output) : $stdout.write(output)
          return 0
        end
        if format == "apng"
          output = render_animation(circuit, options, render_options)
          options[:output] ? File.binwrite(options[:output], output) : $stdout.write(output)
          return 0
        end
        svg = renderer.new.render(circuit, **render_options)
        svg = add_step_banner(svg, options[:step], step, all_steps, options[:theme]) if step
        svg = print_dimensions(svg) if options[:print_template]
        output = case format
        when "svg" then svg
        when "html" then html_viewer(svg, theme: options[:theme], circuit: circuit, render_options: render_options)
        else
          Rasterizer.new.rasterize(svg, format: format, scale: options[:scale],
                                   background: options[:background] || "white", quality: options[:quality], backend: options[:backend],
                                   timeout: options[:render_timeout] || 60)
        end
        options[:output] ? File.binwrite(options[:output], output) : $stdout.write(output)
        0
      rescue OptionParser::ParseError, ArgumentError, JSON::ParserError, Breadkit::Error, Error => e
        warn "bkrender: #{e.message}"
        2
      rescue StandardError => e
        warn "bkrender: #{e.message}"
        2
      end

      private

      def assembly_guide(circuit, render_options, theme)
        steps = circuit.respond_to?(:steps) ? circuit.steps : []
        raise ArgumentError, "circuit has no assembly steps" if steps.empty?

        items = circuit.components.values.group_by { |component| [component.part.id, bom_value(component)] }
        rows = items.sort_by { |(part, value), _| [part, value.to_s] }.map do |(part, value), components|
          cells = [components.length, part, value, components.map(&:ref).sort.join(", ")]
          "<tr>#{cells.map { |cell| "<td>#{CGI.escapeHTML(cell.to_s)}</td>" }.join}</tr>"
        end
        rows << "<tr><td>#{circuit.wires.length}</td><td>Jumper wire</td><td></td><td></td></tr>"
        panels = steps.each_with_index.map do |step, index|
          number = index + 1
          stage = circuit_for_step(circuit, number)
          svg = SvgRenderer.new.render(stage, **render_options.merge(crop: "none", interactive_layers: false))
                           .sub(/\A<\?xml[^>]*\?>\s*/, "")
          heading = CGI.escapeHTML(step[:title] || "Assembly step")
          added_parts = circuit.components.values.select { |component| component.step == number }.map(&:ref).sort
          added_wires = circuit.wires.select { |wire| wire.step == number }.map { |wire| "#{wire.from} → #{wire.to}" }
          changes = []
          changes << "Place #{added_parts.join(', ')}" unless added_parts.empty?
          changes.concat(added_wires.map { |wire| "Connect #{wire}" })
          instructions = changes.map { |change| "<li>#{CGI.escapeHTML(change)}</li>" }.join
          %(<section class="step"><h2>Step #{number} of #{steps.length}: #{heading}</h2><ul>#{instructions}</ul><div class="diagram">#{svg}</div></section>)
        end
        dark = theme == "dark"
        background, surface, foreground, muted = dark ? %w[#111a16 #1d2822 #ecf5ef #b7c9bd] : %w[#f5f7f4 #ffffff #1c3026 #536a5b]
        title = CGI.escapeHTML(circuit.title || "Breadkit assembly guide")
        <<~HTML
          <!doctype html>
          <html lang="en">
          <head>
            <meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
            <title>#{title}</title>
            <style>
              *{box-sizing:border-box}body{margin:0;background:#{background};color:#{foreground};font:16px/1.5 system-ui,sans-serif}
              main{max-width:1120px;margin:auto;padding:32px 20px 64px}h1{font-size:clamp(28px,4vw,44px);line-height:1.1;margin:0 0 10px}
              .intro{color:#{muted};margin:0 0 32px}h2{font-size:22px;line-height:1.25;margin:0 0 16px}
              section{background:#{surface};border:1px solid #{muted};border-radius:14px;padding:24px;margin:0 0 24px}
              table{width:100%;border-collapse:collapse;text-align:left}th,td{padding:10px 12px;border-bottom:1px solid #{muted}}
              th{font-size:12px;text-transform:uppercase;letter-spacing:.08em;color:#{muted}}tr:last-child td{border-bottom:0}
              ul{margin:0 0 20px;padding-left:22px}.diagram{overflow:auto}.diagram svg{display:block;width:min(100%,560px);height:auto;margin:auto}
              @media(max-width:600px){main{padding:20px 12px}section{padding:16px}th,td{padding:8px 5px;font-size:13px}}
              @media print{body{background:white;color:black}main{max-width:none;padding:0}section{break-inside:avoid;border-color:#999}.step{break-before:page}}
            </style>
          </head>
          <body><main><h1>#{title}</h1><p class="intro">#{steps.length} assembly steps · #{circuit.components.length} parts · #{circuit.wires.length} jumper wires</p>
            <section><h2>Bill of materials</h2><table id="bom"><thead><tr><th>Qty</th><th>Part</th><th>Value</th><th>Refs</th></tr></thead><tbody>#{rows.join}</tbody></table></section>
            #{panels.join("\n")}
          </main></body></html>
        HTML
      end

      def bom_value(component)
        return nil unless component.value

        Breadkit::Value.new(component.value, category: component.part.data.dig("render", "shape")).to_s
      rescue ArgumentError
        component.value.to_s
      end

      def render_animation(circuit, options, render_options)
        raise ArgumentError, "APNG is available only in breadboard view" unless options[:view] == "breadboard"

        steps = circuit.respond_to?(:steps) ? circuit.steps : []
        mode = options[:animate] || (steps.empty? ? "states" : "steps")
        if mode == "steps" && options.values_at(:annotations, :focus, :highlight_net, :layer).any?
          raise ArgumentError, "APNG assembly steps cannot use annotations, focus, highlighted nets, or a layer filter"
        end
        frames = if mode == "steps"
          steps.each_index.map do |index|
            number = index + 1
            svg = SvgRenderer.new.render(circuit_for_step(circuit, number), **render_options.merge(crop: "none", interactive_layers: false))
            add_step_banner(svg, number, steps[index], steps, options[:theme])
          end
        else
          circuit.states("all", budget: 256).map do |state|
            SvgRenderer.new.render(circuit, **render_options.merge(crop: "none", state: state, interactive_layers: false))
          end
        end
        raise ArgumentError, "APNG requires at least two #{mode}" unless frames.length >= 2

        rasterizer = Rasterizer.new
        images = frames.map do |svg|
          rasterizer.rasterize(svg, format: "png", scale: options[:scale], backend: options[:backend],
                               timeout: options[:render_timeout] || 60)
        end
        ApngEncoder.new.encode(images, delay_ms: options[:frame_delay] || 800)
      end

      def watch(input, second_input, annotations, output, args)
        root = File.dirname(File.expand_path(input))
        paths = [input, second_input, annotations].compact.map { |path| File.expand_path(path) }
        snapshot = watch_snapshot(root, paths, output)
        warn "bkrender: watching #{root}; press Ctrl-C to stop"
        loop do
          warn "bkrender: rendered #{output}" if run(args.dup).zero?
          loop do
            sleep 0.5
            updated = watch_snapshot(root, paths, output)
            next if updated == snapshot

            snapshot = updated
            break
          end
        end
      rescue Interrupt
        0
      end

      def watch_snapshot(root, paths, output)
        # ponytail: watch nearby circuit and part files; add dependency tracking if broad projects make scanning costly.
        files = paths.dup
        Find.find(root) do |path|
          if File.directory?(path)
            Find.prune if path != root && (File.basename(path).start_with?(".") || File.basename(path) == "node_modules")
          elsif path.end_with?(".bk.rb", ".yml", ".yaml", ".toml", ".json")
            files << path
          end
        end
        files.map { |path| File.expand_path(path) }.uniq.sort.reject { |path| path == File.expand_path(output) }.to_h do |path|
          stat = File.stat(path)
          [path, [stat.mtime.to_r, stat.size]]
        rescue Errno::ENOENT
          [path, nil]
        end
      end

      def validate_step_options(options, format)
        raise ArgumentError, "--step must be a positive integer" unless options[:step].positive?
        raise ArgumentError, "--step is unavailable in #{options[:view]} view" unless options[:view] == "breadboard"
        raise ArgumentError, "--step requires SVG or image output" if format == "html"
        raise ArgumentError, "--step is unavailable with --diff" if options[:diff]
        raise ArgumentError, "--step is unavailable with --print-template" if options[:print_template]
        raise ArgumentError, "--step is unavailable with --annotations" if options[:annotations]
      end

      def select_step(steps, number)
        raise ArgumentError, "circuit has no assembly steps" if steps.empty?

        steps[number - 1] || raise(ArgumentError, "unknown assembly step: #{number}")
      end

      def circuit_for_step(circuit, number)
        visible = ->(item) { !item.step || item.step <= number }
        components = circuit.components.select { |_ref, component| visible.call(component) }
        wires = circuit.wires.select(&visible)
        supplies = circuit.supplies.select(&visible)
        labels = circuit.labels.select(&visible)
        future_refs = (circuit.components.keys - components.keys) + (circuit.supplies.map(&:name) - supplies.map(&:name))
        (wires.flat_map { |wire| [wire.from, wire.to] } + labels.map(&:at)).each do |endpoint|
          ref = endpoint.split(".", 2).first if endpoint.include?(".")
          raise ArgumentError, "step #{number} references #{endpoint} before #{ref} is placed" if future_refs.include?(ref)
        end
        Breadkit::Circuit.new(title: circuit.title, board: circuit.board, components: components, wires: wires,
                              supplies: supplies, labels: labels, expectations: [], lint_disables: [], diagnostics: [],
                              steps: circuit.steps.take(number), source_root: circuit.source_root)
      end

      def add_step_banner(svg, number, step, all_steps, theme)
        inner = svg.sub(/\A<\?xml[^>]*\?>\s*/, "")
        match = inner.match(/\A<svg\b[^>]*\bwidth="([\d.]+)" height="([\d.]+)"/)
        raise Error, "cannot add an assembly step title to this SVG" unless match

        width, height = match.captures.map(&:to_f)
        max_chars = [(width - 24).div(7), 12].max
        titles = all_steps.map { |item| wrap_step_title(item[:title] || "Assembly step", max_chars) }
        banner_height = 50 + titles.map(&:length).max * 18
        heading = "Step #{number} of #{all_steps.length}: #{step[:title] || 'Assembly step'}"
        background, foreground = theme == "dark" ? %w[#0d1420 #f2f6fc] : %w[#f4f7fb #172338]
        inner = inner.sub("<svg ", %(<svg id="step-board" x="0" y="#{banner_height}" ))
        title_lines = [%(<text x="20" y="27" fill="#{foreground}" font-size="15" font-weight="700">Step #{number} of #{all_steps.length}</text>)]
        titles[number - 1].each_with_index do |line, index|
          title_lines << %(<text x="20" y="#{52 + index * 18}" fill="#{foreground}" font-size="12">#{CGI.escapeHTML(line)}</text>)
        end
        %(<?xml version="1.0" encoding="UTF-8"?>\n) +
          %(<svg xmlns="http://www.w3.org/2000/svg" width="#{format('%.2f', width)}" height="#{format('%.2f', height + banner_height)}" viewBox="0 0 #{format('%.2f', width)} #{format('%.2f', height + banner_height)}" role="img" aria-label="#{CGI.escapeHTML(heading)}" data-step="#{number}">\n) +
          %(<title>#{CGI.escapeHTML(heading)}</title><rect width="#{format('%.2f', width)}" height="#{banner_height}" fill="#{background}"/>\n) +
          %(<g id="assembly-step-title" font-family="Helvetica, Arial, sans-serif">#{title_lines.join}</g>\n) +
          %(#{inner}\n</svg>)
      end

      def wrap_step_title(title, max_chars)
        words = title.split.flat_map { |word| word.scan(/.{1,#{max_chars}}/) }
        words.each_with_object([""]) do |word, lines|
          if lines.last.empty? || lines.last.length + word.length + 1 <= max_chars
            lines[-1] = [lines.last, word].reject(&:empty?).join(" ")
          else
            lines << word
          end
        end
      end

      def validate_electrical_view_options(options, format)
        view = options[:view]
        raise ArgumentError, "HTML is unavailable in #{view} view" if format == "html"

        unavailable = { diff: options[:diff], print_template: options[:print_template], rail_pattern: options[:rail_pattern],
                        annotations: options[:annotations], layer: options[:layer], focus: options[:focus],
                        highlight_net: options[:highlight_net], show_nets: options[:show_nets], legend: options[:legend],
                        static: options[:static], crop: options[:crop] != "auto", orientation: options[:orientation] != "portrait",
                        color_by: options[:color_by] != "wire", label_density: options[:label_density] != "full",
                        wire_routing: options[:wire_routing] != "declared", wire_style: options[:wire_style] != "raised" }
        option = unavailable.find { |_name, used| used }&.first
        raise ArgumentError, "--#{option.to_s.tr('_', '-')} is unavailable in #{view} view" if option
      end

      def print_dimensions(svg)
        svg.sub(/(<svg\b[^>]*?\bwidth=")([\d.]+)(" height=")([\d.]+)(")/) do
          "#{$1}#{format('%.2f', $2.to_f * 0.254)}mm#{$3}#{format('%.2f', $4.to_f * 0.254)}mm#{$5}"
        end
      end

      def output_format(options)
        extension = File.extname(options[:output].to_s).downcase
        from_path = { ".svg" => "svg", ".html" => "html", ".png" => "png", ".jpg" => "jpeg", ".jpeg" => "jpeg",
                      ".webp" => "webp", ".pdf" => "pdf", ".apng" => "apng" }[extension]
        raise ArgumentError, "unsupported output extension: #{extension}" if options[:output] && !from_path
        if options[:format] && from_path && options[:format] != from_path
          raise ArgumentError, "--format conflicts with output extension"
        end
        options[:format] || from_path || (options[:diff] ? "html" : "svg")
      end

      def render_diff(before_path, after_path, options, format)
        raise ArgumentError, "--diff requires HTML output" unless format == "html"
        raise ArgumentError, "--diff does not support annotations, state, layer, or focus selection" if options.values_at(:annotations, :state, :layer, :focus, :highlight_net).any?

        before, after = [before_path, after_path].map { |path| Breadkit.load(path) }
        [before, after].zip([before_path, after_path]).each do |circuit, path|
          circuit.diagnostics.each { |item| warn "#{path}: #{item.severity || 'error'}: #{item.message}" }
        end
        return 1 if !options[:force] && [before, after].any? { |circuit| circuit.diagnostics.any? { |item| !%w[warning info].include?(item.severity) } }

        removed = unmatched_wires(before, after).to_h { |id| [id, "removed"] }
        added = unmatched_wires(after, before).to_h { |id| [id, "added"] }
        render_options = { crop: options[:crop], theme: options[:theme], orientation: options[:orientation],
                           show_nets: options[:show_nets], legend: options[:legend], color_by: options[:color_by],
                           rail_pattern: options[:rail_pattern], interactive_layers: !options[:static],
                           label_density: options[:label_density], theme_colors: options[:theme_colors] || {},
                           font_css: options[:font_css], wire_routing: options[:wire_routing],
                           wire_style: options[:wire_style] }
        old_svg = SvgRenderer.new.render(before, **render_options, diff_wires: removed)
        new_svg = SvgRenderer.new.render(after, **render_options, diff_wires: added)
        html = diff_viewer(old_svg, new_svg, theme: options[:theme])
        options[:output] ? File.binwrite(options[:output], html) : $stdout.write(html)
        0
      end

      def unmatched_wires(first, second)
        remaining = second.wires.map { |wire| wire_signature(wire) }.tally
        first.wires.filter_map do |wire|
          signature = wire_signature(wire)
          if remaining.fetch(signature, 0).positive?
            remaining[signature] -= 1
            nil
          else
            wire.id
          end
        end
      end

      def wire_signature(wire)
        [*([wire.from, wire.to].sort), wire.color, wire.route, wire.layer, wire.electrical, wire.dashed]
      end

      def diff_viewer(old_svg, new_svg, theme:)
        background = theme == "dark" ? "#151d19" : "#f1f4f1"
        foreground = theme == "dark" ? "#ecf3ee" : "#203029"
        before = CGI.escapeHTML(html_viewer(old_svg, theme: theme))
        after = CGI.escapeHTML(html_viewer(new_svg, theme: theme))
        <<~HTML
          <!doctype html>
          <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Breadkit wiring diff</title><style>
          *{box-sizing:border-box}body{margin:0;background:#{background};color:#{foreground};font:14px system-ui,sans-serif}
          main{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px;padding:8px}section{min-width:0}
          h2{margin:0 0 8px;font-size:14px;font-weight:600}iframe{width:100%;height:calc(100vh - 48px);border:1px solid currentColor;border-radius:8px}
          @media(max-width:700px){main{grid-template-columns:1fr}iframe{height:70vh}}
          </style></head><body><main>
          <section><h2>Before · removed wires in red</h2><iframe title="Before" sandbox="allow-scripts" srcdoc="#{before}"></iframe></section>
          <section><h2>After · added wires in green</h2><iframe title="After" sandbox="allow-scripts" srcdoc="#{after}"></iframe></section>
          </main></body></html>
        HTML
      end

      def read_annotations(path, input)
        return [] unless path
        data = JSON.parse(File.read(path, encoding: "UTF-8"))
        raise ArgumentError, "unsupported lint JSON schema_version" unless data["schema_version"] == 1
        files = Array(data["files"])
        match = files.find { |file| File.expand_path(file["path"].to_s) == File.expand_path(input) }
        match ||= files.first if files.length == 1
        Array(match && match["offenses"])
      end

      def html_viewer(svg, theme:, circuit: nil, render_options: nil)
        background = theme == "dark" ? "#151d19" : "#f1f4f1"
        foreground = theme == "dark" ? "#ecf3ee" : "#203029"
        states = circuit&.states("all", budget: 256) || []
        selected = render_options&.dig(:state)&.name.to_s
        diagram = viewer_diagrams(svg, states, selected) { |state| SvgRenderer.new.render(circuit, **render_options.merge(state: state)) }
        schematic = if circuit
          initial = SchematicRenderer.new.render(circuit, theme: theme, state: render_options[:state])
          viewer_diagrams(initial, states, selected) { |state| SchematicRenderer.new.render(circuit, theme: theme, state: state) }
        end
        state_control = ""
        if states.length > 1
          options = states.map do |state|
            name = state.name.to_s
            "<option value=\"#{CGI.escapeHTML(name)}\"#{' selected' if name == selected}>#{CGI.escapeHTML(name.empty? ? 'Open' : name)}</option>"
          end.join
          state_control = "<label for=\"state\">State</label><select id=\"state\" aria-label=\"Switch state\">#{options}</select>"
        end
        schematic_panel = if schematic
          <<~PANEL
            <section class="diagram-panel" aria-labelledby="schematic-heading">
              <div class="panel-header"><h2 id="schematic-heading">Schematic</h2><div class="zoom-controls">
                <button type="button" data-pane="schematic" data-action="in" aria-label="Zoom in schematic">+</button>
                <button type="button" data-pane="schematic" data-action="out" aria-label="Zoom out schematic">−</button>
                <button type="button" data-pane="schematic" data-action="fit" aria-label="Fit schematic">Fit</button>
              </div></div>
              <div id="schematic-viewport" class="viewport" tabindex="0" aria-label="Schematic diagram. Arrow keys pan; plus and minus zoom."><div id="schematic-scene" class="scene">#{schematic}</div></div>
            </section>
          PANEL
        end
        <<~HTML
          <!doctype html>
          <html lang="en">
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>Breadkit diagram</title>
            <style>
              *{box-sizing:border-box}body{margin:0;height:100dvh;display:flex;flex-direction:column;background:#{background};color:#{foreground};font:14px system-ui,sans-serif}
              #diagrams{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px;padding:8px;flex:1;min-height:0}
              #diagrams.single{grid-template-columns:1fr}.diagram-panel{display:flex;flex-direction:column;min-width:0;min-height:0;border:1px solid currentColor;border-radius:8px;overflow:hidden}
              .panel-header{display:flex;align-items:center;justify-content:space-between;gap:8px;padding:4px 8px;border-bottom:1px solid currentColor}
              h2{margin:0;font-size:14px;font-weight:600}.zoom-controls{display:flex;gap:2px}
              .viewport{position:relative;flex:1;min-height:0;overflow:hidden;touch-action:none;cursor:grab}.viewport.dragging{cursor:grabbing}.viewport:focus-visible{outline:2px solid currentColor;outline-offset:-2px}
              .scene{position:absolute;left:0;top:0;transform-origin:0 0;will-change:transform}.scene svg{display:block;max-width:none}
              .scene svg[data-viewer-state]:not([data-active]){display:none}
              .net-muted{opacity:.18!important}
              #toolbar{display:flex;align-items:center;gap:8px;padding:8px 12px;border-bottom:1px solid currentColor;background:#{background}}
              button{color:inherit;background:transparent;border:0;border-radius:4px;min-width:36px;height:32px;font:inherit;cursor:pointer}button:hover,button:focus-visible{outline:2px solid currentColor}
              select{color:inherit;background:#{background};border:1px solid currentColor;border-radius:4px;font:inherit;max-width:220px;padding:4px}
              .sr-only{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;border:0}
              [data-switch]{cursor:pointer}[data-switch]:focus-visible{filter:drop-shadow(0 0 3px currentColor)}
              @media(max-width:850px){body{height:auto;min-height:100dvh}#diagrams.dual{grid-template-columns:1fr;flex:none}.dual .diagram-panel{height:68vh}}
            </style>
          </head>
          <body>
            <div id="toolbar" role="toolbar" aria-label="Diagram controls">
              #{state_control}
              <label for="net">Net</label><select id="net" aria-label="Highlight net"><option value="">All nets</option></select>
            </div>
            <main id="diagrams" class="#{schematic ? 'dual' : 'single'}">
              <section class="diagram-panel" aria-labelledby="breadboard-heading">
                <div class="panel-header"><h2 id="breadboard-heading">Breadboard</h2><div class="zoom-controls">
                  <button type="button" data-pane="board" data-action="in" aria-label="Zoom in breadboard">+</button>
                  <button type="button" data-pane="board" data-action="out" aria-label="Zoom out breadboard">−</button>
                  <button type="button" data-pane="board" data-action="fit" aria-label="Fit breadboard">Fit</button>
                </div></div>
                <div id="viewport" class="viewport" tabindex="0" aria-label="Interactive breadboard diagram. Arrow keys pan; plus and minus zoom."><div id="scene" class="scene">#{diagram}</div></div>
              </section>
              #{schematic_panel}
            </main>
            <span id="viewer-status" class="sr-only" role="status"></span>
            <script>
              const stateSelect=document.getElementById('state'),netSelect=document.getElementById('net'),status=document.getElementById('viewer-status');
              let selectedNet='',hoverNet='';
              const panes={};
              const makePane=(key,viewportId,sceneId)=>{
                const viewport=document.getElementById(viewportId),scene=document.getElementById(sceneId);
                let svg=scene.querySelector('[data-active]')||scene.querySelector('svg'),scale=1,x=0,y=0,dragging=false,lastX=0,lastY=0;
                const paint=()=>{scene.style.transform=`translate(${x}px,${y}px) scale(${scale})`};
                const fit=()=>{const w=Number(svg.getAttribute('width')),h=Number(svg.getAttribute('height'));
                  scene.style.width=`${w}px`;scene.style.height=`${h}px`;
                  scale=Math.min((viewport.clientWidth-32)/w,(viewport.clientHeight-32)/h);x=(viewport.clientWidth-w*scale)/2;y=(viewport.clientHeight-h*scale)/2;paint()};
                const zoom=(factor,cx,cy)=>{const next=Math.max(.1,Math.min(12,scale*factor));x=cx-(cx-x)*next/scale;y=cy-(cy-y)*next/scale;scale=next;paint()};
                const showState=name=>{const next=[...scene.querySelectorAll('[data-viewer-state]')].find(node=>node.getAttribute('data-viewer-state')===name);
                  if(!next)return;svg.removeAttribute('data-active');svg=next;svg.setAttribute('data-active','');fit()};
                viewport.addEventListener('wheel',event=>{event.preventDefault();const box=viewport.getBoundingClientRect();zoom(event.deltaY<0?1.15:1/1.15,event.clientX-box.left,event.clientY-box.top)},{passive:false});
                viewport.addEventListener('pointerdown',event=>{if(event.target.closest('[data-layer-button],[data-switch]'))return;dragging=true;lastX=event.clientX;lastY=event.clientY;viewport.classList.add('dragging');viewport.setPointerCapture(event.pointerId)});
                viewport.addEventListener('pointermove',event=>{if(dragging){x+=event.clientX-lastX;y+=event.clientY-lastY;lastX=event.clientX;lastY=event.clientY;paint();return}
                  const net=event.target.closest('[data-net]')?.getAttribute('data-net')||'';if(net===hoverNet)return;hoverNet=net;paintNet()});
                const endDrag=()=>{dragging=false;viewport.classList.remove('dragging')};viewport.addEventListener('pointerup',endDrag);viewport.addEventListener('pointercancel',endDrag);
                viewport.addEventListener('pointerleave',()=>{if(dragging)return;hoverNet='';paintNet()});
                viewport.addEventListener('keydown',event=>{if(event.defaultPrevented)return;
                  if(event.key==='+'||event.key==='=')zoom(1.25,viewport.clientWidth/2,viewport.clientHeight/2);
                  else if(event.key==='-')zoom(.8,viewport.clientWidth/2,viewport.clientHeight/2);
                  else if(event.key==='0')fit();
                  else if(event.key==='ArrowLeft')x+=24;else if(event.key==='ArrowRight')x-=24;
                  else if(event.key==='ArrowUp')y+=24;else if(event.key==='ArrowDown')y-=24;else return;
                  paint();event.preventDefault()});
                panes[key]={scene,active:()=>svg,fit,zoom,showState};
              };
              makePane('board','viewport','scene');
              if(document.getElementById('schematic-viewport'))makePane('schematic','schematic-viewport','schematic-scene');
              const paintNet=()=>{const net=hoverNet||selectedNet;
                Object.values(panes).forEach(pane=>pane.active().querySelectorAll('[data-net]').forEach(node=>node.classList.toggle('net-muted',!!net&&node.getAttribute('data-net')!==net)))};
              const populateNets=()=>{const names=[...new Set(Object.values(panes).flatMap(pane=>[...pane.active().querySelectorAll('[data-net]')].map(node=>node.getAttribute('data-net'))))].sort((a,b)=>a.localeCompare(b,undefined,{numeric:true}));
                netSelect.replaceChildren(new Option('All nets',''),...names.map(name=>new Option(name,name)));selectedNet='';netSelect.value='';paintNet()};
              const selectState=name=>{Object.values(panes).forEach(pane=>pane.showState(name));stateSelect.value=name;hoverNet='';populateNets();
                status.textContent=`${name||'Open'} switch state selected`};
              if(stateSelect){const board=panes.board.scene;
                board.querySelectorAll('[data-switch]').forEach(node=>{node.setAttribute('tabindex','0');node.setAttribute('role','button');node.setAttribute('aria-label',`Toggle ${node.getAttribute('data-switch')}`)});
                const switchRefs=[...new Set([...panes.board.active().querySelectorAll('[data-switch]')].map(node=>node.getAttribute('data-switch')))];
                const toggleSwitch=ref=>{const active=new Set(stateSelect.value.split(',').filter(Boolean));active.has(ref)?active.delete(ref):active.add(ref);
                  selectState(switchRefs.filter(name=>active.has(name)).join(','));[...panes.board.active().querySelectorAll('[data-switch]')].find(node=>node.getAttribute('data-switch')===ref)?.focus()};
                stateSelect.addEventListener('change',()=>selectState(stateSelect.value));
                board.addEventListener('click',event=>{const button=event.target.closest('[data-switch]');if(button)toggleSwitch(button.getAttribute('data-switch'))});
                board.addEventListener('keydown',event=>{const button=event.target.closest('[data-switch]');if(!button||(event.key!=='Enter'&&event.key!==' '))return;
                  event.preventDefault();toggleSwitch(button.getAttribute('data-switch'))})}
              netSelect.addEventListener('change',()=>{selectedNet=netSelect.value;paintNet();status.textContent=selectedNet?`${selectedNet} highlighted in both diagrams`:'All nets shown'});
              document.querySelectorAll('[data-action]').forEach(button=>button.addEventListener('click',()=>{const pane=panes[button.getAttribute('data-pane')],action=button.getAttribute('data-action');
                if(action==='fit')pane.fit();else pane.zoom(action==='in'?1.25:.8,pane.scene.parentElement.clientWidth/2,pane.scene.parentElement.clientHeight/2)}));
              window.addEventListener('resize',()=>Object.values(panes).forEach(pane=>pane.fit()));populateNets();Object.values(panes).forEach(pane=>pane.fit());
            </script>
          </body>
          </html>
        HTML
      end

      def viewer_diagrams(original, states, selected)
        return original.sub(/\A<\?xml[^>]*\?>\s*/, "") if states.length < 2

        states.map do |state|
          state_svg = state.name.to_s == selected ? original : yield(state)
          state_svg.sub(/\A<\?xml[^>]*\?>\s*/, "")
                   .sub("<svg ", "<svg data-viewer-state=\"#{CGI.escapeHTML(state.name.to_s)}\"#{' data-active' if state.name.to_s == selected} ")
        end.join
      end
    end
  end
end
