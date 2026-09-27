# frozen_string_literal: true

require "json"

module Breadkit
  module Render
    module Theme
      FONT_FORMATS = { ".ttf" => ["font/ttf", "\x00\x01\x00\x00".b], ".otf" => ["font/otf", "OTTO"],
                       ".woff" => ["font/woff", "wOFF"], ".woff2" => ["font/woff2", "wOF2"] }.freeze
      MAX_FONT_SIZE = 5 * 1024 * 1024

      module_function

      def load(path)
        data = JSON.parse(File.read(path, encoding: "UTF-8"))
        raise Error, "theme must be a JSON object" unless data.is_a?(Hash)
        unknown = data.keys - %w[base colors]
        raise Error, "unknown theme option: #{unknown.join(', ')}" unless unknown.empty?

        base = data.fetch("base", "light")
        raise Error, "unknown base theme: #{base}" unless SvgRenderer::COLORS.key?(base)

        colors = data.fetch("colors", {})
        raise Error, "theme colors must be an object" unless colors.is_a?(Hash)
        colors.each do |key, value|
          raise Error, "unknown theme color: #{key}" unless SvgRenderer::COLORS.fetch(base).key?(key.to_sym)
          raise Error, "invalid theme color for #{key}: use #RRGGBB" unless value.is_a?(String) && value.match?(/\A#[0-9a-fA-F]{6}\z/)
        end
        { base: base, colors: colors.transform_keys(&:to_sym) }
      rescue JSON::ParserError => e
        raise Error, "invalid theme JSON: #{e.message}"
      end

      def font(path)
        format = FONT_FORMATS[File.extname(path).downcase]
        raise Error, "unsupported font format: use TTF, OTF, WOFF, or WOFF2" unless format
        raise Error, "font file is too large (limit: 5 MiB)" if File.size(path) > MAX_FONT_SIZE

        bytes = File.binread(path)
        raise Error, "invalid font signature" unless bytes.start_with?(format.last)

        "@font-face{font-family:BreadkitEmbedded;src:url(data:#{format.first};base64,#{[bytes].pack('m0')})}"
      end
    end
  end
end
