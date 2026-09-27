# frozen_string_literal: true

require "tmpdir"

module Breadkit
  module Render
    class Rasterizer
      class TimeoutError < Error; end

      def rasterize(svg, format:, scale: 2.0, background: "white", quality: 90, backend: "auto", timeout: 60)
        format = format.to_s
        backend = backend.to_s
        raise Error, "unsupported raster format: #{format}" unless %w[png jpeg webp pdf].include?(format)
        raise Error, "unsupported raster backend: #{backend}" unless %w[auto rsvg resvg vips magick chrome].include?(backend)

        begin
          scale = Float(scale)
        rescue ArgumentError, TypeError
          raise Error, "scale must be a positive finite number"
        end
        raise Error, "scale must be a positive finite number" unless scale.finite? && scale.positive?
        raise Error, "quality must be an integer between 0 and 100" unless quality.is_a?(Integer) && quality.between?(0, 100)
        raise Error, "render timeout must be a positive finite number" unless timeout.is_a?(Numeric) && timeout.finite? && timeout.positive?
        background = color(background) if format == "jpeg"

        candidates = case backend
        when "rsvg" then ["rsvg"]
        when "resvg" then ["resvg"]
        when "chrome" then ["chrome"]
        when "magick" then ["magick"]
        when "vips" then ["vips"]
        else case format
        when "png" then %w[rsvg resvg vips magick chrome]
        when "pdf" then %w[rsvg]
        else %w[vips magick]
        end
        end
        candidates.each do |name|
          next unless supports?(name, format)
          begin
            return send(name, svg, format, scale, background, quality, timeout)
          rescue Error => e
            raise if backend != "auto" || e.is_a?(TimeoutError)
          end
        end
        raise Error, "no conversion backend found for #{format}; install librsvg, resvg, ruby-vips, ImageMagick, or Chrome"
      end

      private

      def supports?(name, format)
        return !!executable("rsvg-convert") if name == "rsvg" && %w[png pdf].include?(format)
        return !!executable("resvg") if name == "resvg" && format == "png"
        return !!chrome_binary if name == "chrome" && format == "png"
        return !!magick_command if name == "magick" && format != "pdf"
        return false unless name == "vips" && format != "pdf"
        require "vips"
        true
      rescue LoadError
        false
      end

      def rsvg(svg, format, scale, _background, _quality, timeout)
        stdout, stderr, status = capture_command(executable("rsvg-convert"), "--format=#{format}", "--zoom=#{scale}", svg: svg, timeout: timeout)
        raise Error, "rsvg-convert failed: #{stderr}" unless status.success?
        stdout
      end

      def resvg(svg, _format, scale, _background, _quality, timeout)
        stdout, stderr, status = capture_command(executable("resvg"), "-z", scale.to_s, "-", "-c", svg: svg, timeout: timeout)
        raise Error, "resvg failed: #{stderr}" unless status.success?

        stdout
      end

      def chrome(svg, _format, scale, background, _quality, timeout)
        raise Error, "Chrome PNG supports only an opaque white background" unless background == "white"

        width, height = chrome_dimensions(svg, scale)
        Dir.mktmpdir("breadkit-chrome-") do |dir|
          html_path = File.join(dir, "image.html")
          png_path = File.join(dir, "image.png")
          error_path = File.join(dir, "chrome.log")
          encoded = [svg].pack("m0")
          File.write(html_path, %(<html><head><meta charset="utf-8"><style>html,body{margin:0;padding:0}img{display:block;width:#{width}px;height:#{height}px}</style></head><body><img src="data:image/svg+xml;base64,#{encoded}"></body></html>))
          command = [chrome_binary, "--headless", "--disable-gpu", "--disable-background-networking", "--no-first-run",
                     "--no-default-browser-check", "--hide-scrollbars", "--force-device-scale-factor=1",
                     "--window-size=#{width},#{height}", "--screenshot=#{png_path}",
                     "--user-data-dir=#{File.join(dir, 'profile')}", "file://#{html_path}"]
          process_options = { out: File::NULL, err: error_path }
          process_options[:pgroup] = true unless RbConfig::CONFIG["host_os"].match?(/mswin|mingw/i)
          pid = Process.spawn(*command, **process_options)
          begin
            deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
            loop do
              if File.file?(png_path)
                bytes = File.binread(png_path)
                if bytes.start_with?("\x89PNG\r\n\x1a\n".b) && bytes.end_with?("IEND\xAE\x42\x60\x82".b)
                  actual = bytes.byteslice(16, 8).unpack("N2")
                  raise Error, "Chrome PNG dimensions #{actual.join('x')} differ from #{width}x#{height}" unless actual == [width, height]
                  return bytes
                end
              end
              break if Process.waitpid(pid, Process::WNOHANG)
              raise TimeoutError, "Chrome timed out after #{timeout} seconds" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

              sleep 0.02
            end
            raise Error, "Chrome failed: #{File.read(error_path).lines.last.to_s.strip}"
          ensure
            signal = process_options[:pgroup] ? -pid : pid
            begin
              Process.kill("KILL", signal)
              Process.waitpid(pid)
            rescue Errno::ESRCH, Errno::ECHILD
              nil
            end
          end
        end
      end

      def chrome_dimensions(svg, scale)
        match = /<svg\b[^>]*\bwidth="([\d.]+)"\s+height="([\d.]+)"/.match(svg)
        raise Error, "Chrome needs SVG width and height dimensions" unless match

        dimensions = match.captures.map { |value| (value.to_f * scale).round }
        raise Error, "Chrome dimensions must be 1 to 16384 pixels" unless dimensions.all? { |value| value.between?(1, 16_384) }
        raise Error, "Chrome image exceeds 25 million pixels" if dimensions.inject(:*) > 25_000_000

        dimensions
      end

      def chrome_binary
        configured = ENV["BREADKIT_CHROME"]
        return configured if configured && File.executable?(configured)

        %w[google-chrome chromium chromium-browser chrome].each do |name|
          path = executable(name)
          return path if path
        end
        mac = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        mac if File.executable?(mac)
      end

      def magick(svg, format, scale, background, quality, timeout)
        command = magick_command
        background_color = format == "jpeg" ? "##{background.map { |channel| channel.to_s(16).rjust(2, "0") }.join}" : "none"
        args = ["-density", (96 * scale).to_s, "-background", background_color]
        font = font_file
        args.concat(["-font", font]) if font
        args << "svg:-"
        args += ["-background", background_color, "-alpha", "remove"] if format == "jpeg"
        args += ["-quality", quality.to_s] if %w[jpeg webp].include?(format)
        args << "#{format}:-"
        stdout, stderr, status = capture_command(command, *args, svg: svg, timeout: timeout)
        raise Error, "ImageMagick failed: #{stderr}" unless status.success?
        stdout
      end

      def vips(svg, format, scale, background, quality, _timeout)
        image = Vips::Image.svgload_buffer(svg, scale: scale.to_f)
        if format == "jpeg"
          image = image.flatten(background: background) if image.has_alpha?
          image.jpegsave_buffer(Q: quality.to_i)
        elsif format == "webp"
          image.webpsave_buffer(Q: quality.to_i)
        else
          image.pngsave_buffer
        end
      rescue StandardError => e
        raise Error, "libvips failed: #{e.message}"
      end

      def capture_command(*command, svg:, timeout:)
        Open3.popen3(*command) do |stdin, stdout, stderr, process|
          [stdin, stdout, stderr].each(&:binmode)
          writer = Thread.new do
            stdin.write(svg)
          rescue Errno::EPIPE, IOError
            nil
          ensure
            stdin.close
          end
          output = Thread.new { stdout.read }
          errors = Thread.new { stderr.read }
          unless process.join(timeout)
            begin
              Process.kill("KILL", process.pid)
            rescue Errno::ESRCH
              nil
            end
            process.join
            raise TimeoutError, "#{File.basename(command.first)} timed out after #{timeout} seconds"
          end
          raise TimeoutError, "#{File.basename(command.first)} output timed out after #{timeout} seconds" unless output.join(timeout) && errors.join(timeout)
          [output.value, errors.value, process.value]
        ensure
          stdin.close unless stdin.closed?
          [writer, output, errors].each { |thread| thread.kill if thread&.alive? }
        end
      end

      def color(value)
        named = { "aqua" => [0, 255, 255], "black" => [0, 0, 0], "blue" => [0, 0, 255],
                  "fuchsia" => [255, 0, 255], "gray" => [128, 128, 128], "green" => [0, 128, 0],
                  "lime" => [0, 255, 0], "maroon" => [128, 0, 0], "navy" => [0, 0, 128],
                  "olive" => [128, 128, 0], "purple" => [128, 0, 128], "red" => [255, 0, 0],
                  "silver" => [192, 192, 192], "teal" => [0, 128, 128], "white" => [255, 255, 255],
                  "yellow" => [255, 255, 0] }
        name = value.to_s.downcase
        return named[name] if named.key?(name)

        hex = value.to_s.delete_prefix("#")
        raise Error, "unsupported JPEG background color: #{value}; use a basic CSS color name, #RGB, or #RRGGBB" unless /\A(?:[0-9a-f]{3}|[0-9a-f]{6})\z/i.match?(hex)

        hex = hex.chars.map { |char| char * 2 }.join if hex.length == 3
        hex.scan(/../).map { |part| part.to_i(16) }
      end

      def executable(name)
        extensions = RbConfig::CONFIG["host_os"].match?(/mswin|mingw/i) ? ENV.fetch("PATHEXT", ".EXE;.COM;.BAT;.CMD").split(";") : [""]
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |dir|
          extensions.each do |extension|
            path = File.join(dir, "#{name}#{extension}")
            return path if File.executable?(path)
          end
        end
        nil
      end

      def magick_command
        executable("magick") || (executable("convert") unless RbConfig::CONFIG["host_os"].match?(/mswin|mingw/i))
      end

      def font_file
        candidates = if RbConfig::CONFIG["host_os"].match?(/darwin/i)
          ["/System/Library/Fonts/Supplemental/Arial Unicode.ttf", "/System/Library/Fonts/Supplemental/Arial.ttf"]
        elsif RbConfig::CONFIG["host_os"].match?(/mswin|mingw/i)
          ["C:/Windows/Fonts/arial.ttf"]
        else
          ["/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]
        end
        candidates.find { |path| File.file?(path) }
      end
    end
  end
end
