# frozen_string_literal: true

require "rexml/document"

module Breadkit
  module Render
    class SvgTemplate
      ELEMENTS = %w[g circle ellipse rect line path polygon polyline text title].freeze
      ATTRIBUTES = %w[x y x1 y1 x2 y2 cx cy r rx ry width height points d transform fill stroke stroke-width
                      stroke-linecap stroke-linejoin fill-opacity stroke-opacity opacity font-size font-weight text-anchor].freeze
      NUMERIC = %w[x y x1 y1 x2 y2 cx cy r rx ry width height stroke-width fill-opacity stroke-opacity opacity font-size].freeze
      PAINT = %w[fill stroke].freeze
      VARIABLES = %w[ref value fill stroke text_color].freeze

      def initialize(source)
        raise Error, "part SVG template exceeds 16 KiB" if source.bytesize > 16 * 1024
        raise Error, "part SVG template contains unsupported markup" if source.include?("<!") || source.include?("<?")

        @source = source
      end

      def render(values)
        expanded = @source.gsub(/\{\{(.*?)\}\}/m) do
          key = Regexp.last_match(1)
          raise Error, "unknown part SVG template variable: #{key}" unless VARIABLES.include?(key)

          CGI.escapeHTML(values.fetch(key).to_s)
        end
        raise Error, "invalid part SVG template variable" if expanded.include?("{{") || expanded.include?("}}")
        raise Error, "expanded part SVG template exceeds 32 KiB" if expanded.bytesize > 32 * 1024

        root = REXML::Document.new("<root>#{expanded}</root>").root
        @nodes = 0
        root.children.map { |child| serialize(child, 0) }.join
      rescue REXML::ParseException => e
        raise Error, "invalid part SVG template: #{e.message.lines.first.to_s.strip}"
      end

      private

      def serialize(node, depth)
        raise Error, "part SVG template is too deeply nested" if depth > 8
        @nodes += 1
        raise Error, "part SVG template has too many nodes" if @nodes > 128
        if node.is_a?(REXML::Text)
          return CGI.escapeHTML(node.value)
        end
        raise Error, "unsupported part SVG template node" unless node.is_a?(REXML::Element)
        raise Error, "unsupported part SVG template element: #{node.name}" unless ELEMENTS.include?(node.name)

        attrs = node.attributes.map do |key, value|
          raise Error, "unsupported part SVG template attribute: #{key}" unless ATTRIBUTES.include?(key)
          validate_attribute(key, value)
          %(#{key}="#{CGI.escapeHTML(value)}")
        end
        content = node.children.map { |child| serialize(child, depth + 1) }.join
        "<#{node.name}#{attrs.empty? ? '' : ' ' + attrs.join(' ')}>#{content}</#{node.name}>"
      end

      def validate_attribute(key, value)
        if PAINT.include?(key)
          raise Error, "invalid part SVG template paint: #{value}" unless value == "none" || Breadkit::Color.valid?(value)
        elsif NUMERIC.include?(key)
          valid = /\A[-+]?(?:\d+(?:\.\d*)?|\.\d+)\z/.match?(value) && value.to_f.abs <= 10_000
          raise Error, "invalid part SVG template number: #{value}" unless valid
        elsif key == "d"
          raise Error, "invalid part SVG template path" unless value.bytesize <= 4096 && /\A[\d\s,\.\-+MmLlHhVvCcSsQqTtAaZz]*\z/.match?(value)
        elsif key == "points"
          raise Error, "invalid part SVG template points" unless /\A[\d\s,\.\-+]*\z/.match?(value)
        elsif key == "transform"
          raise Error, "invalid part SVG template transform" unless value.match?(/\A(?:\s*(?:translate|rotate|scale|matrix)\([\d\s,\.\-+]+\)\s*)+\z/)
        elsif key == "stroke-linecap"
          raise Error, "invalid part SVG template line cap" unless %w[butt round square].include?(value)
        elsif key == "stroke-linejoin"
          raise Error, "invalid part SVG template line join" unless %w[miter round bevel].include?(value)
        elsif key == "text-anchor"
          raise Error, "invalid part SVG template text anchor" unless %w[start middle end].include?(value)
        elsif key == "font-weight"
          raise Error, "invalid part SVG template font weight" unless %w[normal bold 100 200 300 400 500 600 700 800 900].include?(value)
        end
      end
    end
  end
end
