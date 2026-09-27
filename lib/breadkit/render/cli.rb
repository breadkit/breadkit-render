# frozen_string_literal: true

require "optparse"
require "cgi/escape"

module Breadkit
  module Render
    class CLI
      def run(argv)
        options = { scale: 2.0, theme: "light", orientation: "portrait", color_by: "wire", crop: "auto", backend: "auto", quality: 90,
                    view: "breadboard", label_density: "full" }
        parser = OptionParser.new do |opts|
          opts.banner = "Usage: bkrender [options] INPUT"
          opts.on("-o", "--output PATH") { |value| options[:output] = value }
          opts.on("-f", "--format FORMAT", %w[svg html png jpeg jpg webp pdf]) { |value| options[:format] = value == "jpg" ? "jpeg" : value }
          opts.on("--view NAME", %w[breadboard netlist schematic]) { |value| options[:view] = value }
          opts.on("--scale N", Float) { |value| options[:scale] = value }
          opts.on("--theme NAME", %w[light dark print]) { |value| options[:theme] = value }
          opts.on("--orientation NAME", %w[portrait landscape]) { |value| options[:orientation] = value }
          opts.on("--rail-pattern PATTERN", SvgRenderer::RAIL_PATTERNS) { |value| options[:rail_pattern] = value }
          opts.on("--color-by MODE", %w[wire net]) { |value| options[:color_by] = value }
          opts.on("--label-density MODE", SvgRenderer::LABEL_DENSITIES) { |value| options[:label_density] = value }
          opts.on("--show-nets") { options[:show_nets] = true }
          opts.on("--legend") { options[:legend] = true }
          opts.on("--crop MODE", %w[auto none]) { |value| options[:crop] = value }
          opts.on("--annotations FILE") { |value| options[:annotations] = value }
          opts.on("--state NAME") { |value| options[:state] = value }
          opts.on("--step N", Integer) { |value| options[:step] = value }
          opts.on("--layer NAME") { |value| options[:layer] = value }
          opts.on("--focus REF") { |value| options[:focus] = value }
          opts.on("--highlight-net NAME") { |value| options[:highlight_net] = value }
          opts.on("--diff") { options[:diff] = true }
          opts.on("--backend NAME", %w[auto rsvg vips magick]) { |value| options[:backend] = value }
          opts.on("--background COLOR") { |value| options[:background] = value }
          opts.on("--static") { options[:static] = true }
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
        validate_electrical_view_options(options, format) unless options[:view] == "breadboard"
        validate_step_options(options, format) if options[:step]
        if options[:print_template]
          raise ArgumentError, "--print-template requires PDF output" unless format == "pdf"
          options.merge!(theme: "print", crop: "none", scale: 1.0, static: true)
        end
        raise ArgumentError, "--background is only supported for JPEG" if options[:background] && format != "jpeg"
        raise ArgumentError, "cannot write binary image data to a terminal; use -o PATH" if !%w[svg html].include?(format) && !options[:output] && $stdout.tty?
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
        state = circuit.states("all").find { |candidate| candidate.name == options[:state] } if options[:state]
        raise ArgumentError, "unknown circuit state: #{options[:state]}" if options[:state] && !state
        render_options = if %w[netlist schematic].include?(options[:view])
          { theme: options[:theme], state: state }
        else
          { crop: step ? "none" : options[:crop], theme: options[:theme], orientation: options[:orientation],
            show_nets: options[:show_nets], legend: options[:legend], color_by: options[:color_by],
            annotations: read_annotations(options[:annotations], input), rail_pattern: options[:rail_pattern],
            interactive_layers: !step && %w[svg html].include?(format) && !options[:static] && !options[:layer],
            state: state, active_layer: options[:layer], focus: options[:focus],
            highlight_net: options[:highlight_net], label_density: options[:label_density] }
        end
        renderer = { "breadboard" => SvgRenderer, "netlist" => NetlistRenderer,
                     "schematic" => SchematicRenderer }.fetch(options[:view])
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
                        color_by: options[:color_by] != "wire", label_density: options[:label_density] != "full" }
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
                      ".webp" => "webp", ".pdf" => "pdf" }[extension]
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
                           label_density: options[:label_density] }
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
        diagram = svg.sub(/\A<\?xml[^>]*\?>\s*/, "")
        state_control = ""
        states = circuit&.states("all") || []
        if states.length > 1
          selected = render_options[:state]&.name.to_s
          diagram = states.map do |state|
            state_svg = state.name.to_s == selected ? svg : SvgRenderer.new.render(circuit, **render_options.merge(state: state))
            state_svg.sub(/\A<\?xml[^>]*\?>\s*/, "")
                     .sub("<svg ", "<svg data-viewer-state=\"#{CGI.escapeHTML(state.name.to_s)}\"#{' data-active' if state.name.to_s == selected} ")
          end.join
          options = states.map do |state|
            name = state.name.to_s
            "<option value=\"#{CGI.escapeHTML(name)}\"#{' selected' if name == selected}>#{CGI.escapeHTML(name.empty? ? 'Open' : name)}</option>"
          end.join
          state_control = "<label for=\"state\">State</label><select id=\"state\" aria-label=\"Switch state\">#{options}</select>"
        end
        <<~HTML
          <!doctype html>
          <html lang="en">
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>Breadkit diagram</title>
            <style>
              *{box-sizing:border-box}body{margin:0;background:#{background};color:#{foreground};font:14px system-ui,sans-serif}
              #viewport{position:fixed;inset:0;overflow:hidden;touch-action:none;cursor:grab}#viewport.dragging{cursor:grabbing}
              #scene{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;transform-origin:0 0;will-change:transform}
              #scene svg{display:block;width:100%;height:100%;overflow:hidden}#scene.ready{inset:auto;left:0;top:0;display:block;overflow:hidden}#scene.ready svg{width:auto;height:auto;max-width:none}
              #scene svg[data-viewer-state]:not([data-active]){display:none}
              .net-muted{opacity:.18!important}
              #toolbar{position:fixed;z-index:2;top:16px;right:16px;display:flex;gap:4px;padding:4px;border:1px solid currentColor;border-radius:8px;background:#{background}}
              button{color:inherit;background:transparent;border:0;border-radius:4px;min-width:36px;height:32px;font:inherit;cursor:pointer}button:hover,button:focus-visible{outline:2px solid currentColor}
              #toolbar label{align-self:center;padding:0 4px}select{color:inherit;background:#{background};border:1px solid currentColor;border-radius:4px;font:inherit}
            </style>
          </head>
          <body>
            <div id="viewport" aria-label="Interactive breadboard diagram"><div id="scene">#{diagram}</div></div>
            <div id="toolbar" role="toolbar" aria-label="Diagram controls">
              #{state_control}
              <button type="button" data-action="in" aria-label="Zoom in">+</button>
              <button type="button" data-action="out" aria-label="Zoom out">−</button>
              <button type="button" data-action="fit" aria-label="Fit diagram">Fit</button>
            </div>
            <script>
              const viewport=document.getElementById('viewport'),scene=document.getElementById('scene'),stateSelect=document.getElementById('state');
              let svg=scene.querySelector('[data-active]')||scene.querySelector('svg');
              let scale=1,x=0,y=0,dragging=false,lastX=0,lastY=0,activeNet=null;
              const paint=()=>{scene.style.transform=`translate(${x}px,${y}px) scale(${scale})`};
              const fit=()=>{scene.classList.add('ready');const w=Number(svg.getAttribute('width')),h=Number(svg.getAttribute('height'));
                scene.style.width=`${w}px`;scene.style.height=`${h}px`;
                scale=Math.min((viewport.clientWidth-32)/w,(viewport.clientHeight-32)/h);x=(viewport.clientWidth-w*scale)/2;y=(viewport.clientHeight-h*scale)/2;paint()};
              const zoom=(factor,cx,cy)=>{const next=Math.max(.1,Math.min(12,scale*factor));x=cx-(cx-x)*next/scale;y=cy-(cy-y)*next/scale;scale=next;paint()};
              viewport.addEventListener('wheel',event=>{event.preventDefault();const box=viewport.getBoundingClientRect();zoom(event.deltaY<0?1.15:1/1.15,event.clientX-box.left,event.clientY-box.top)},{passive:false});
              viewport.addEventListener('pointerdown',event=>{if(event.target.closest('[data-layer-button],[data-switch]'))return;dragging=true;lastX=event.clientX;lastY=event.clientY;viewport.classList.add('dragging');viewport.setPointerCapture(event.pointerId)});
              viewport.addEventListener('pointermove',event=>{if(dragging){x+=event.clientX-lastX;y+=event.clientY-lastY;lastX=event.clientX;lastY=event.clientY;paint();return}
                const net=event.target.closest('[data-net]')?.getAttribute('data-net')||null;if(net===activeNet)return;activeNet=net;
                scene.querySelectorAll('[data-net]').forEach(node=>node.classList.toggle('net-muted',!!net&&node.getAttribute('data-net')!==net))});
              const endDrag=()=>{dragging=false;viewport.classList.remove('dragging')};viewport.addEventListener('pointerup',endDrag);viewport.addEventListener('pointercancel',endDrag);
              viewport.addEventListener('pointerleave',()=>{if(dragging)return;activeNet=null;scene.querySelectorAll('.net-muted').forEach(node=>node.classList.remove('net-muted'))});
              const selectState=name=>{const next=[...scene.querySelectorAll('[data-viewer-state]')].find(node=>node.getAttribute('data-viewer-state')===name);
                if(!next)return;svg.removeAttribute('data-active');svg=next;svg.setAttribute('data-active','');stateSelect.value=name;
                activeNet=null;scene.querySelectorAll('.net-muted').forEach(node=>node.classList.remove('net-muted'));fit()};
              if(stateSelect){const switchRefs=[...new Set([...svg.querySelectorAll('[data-switch]')].map(node=>node.getAttribute('data-switch')))];
                stateSelect.addEventListener('change',()=>selectState(stateSelect.value));
                scene.addEventListener('click',event=>{const button=event.target.closest('[data-switch]');if(!button)return;
                  const active=new Set(stateSelect.value.split(',').filter(Boolean)),ref=button.getAttribute('data-switch');
                  active.has(ref)?active.delete(ref):active.add(ref);selectState(switchRefs.filter(name=>active.has(name)).join(','))})}
              document.querySelectorAll('[data-action]').forEach(button=>button.addEventListener('click',()=>{const action=button.getAttribute('data-action');if(action==='fit')fit();else zoom(action==='in'?1.25:.8,viewport.clientWidth/2,viewport.clientHeight/2)}));
              window.addEventListener('resize',fit);fit();
            </script>
          </body>
          </html>
        HTML
      end
    end
  end
end
