# frozen_string_literal: true

require "zlib"

module Breadkit
  module Render
    class ApngEncoder
      SIGNATURE = "\x89PNG\r\n\x1a\n".b.freeze

      def encode(images, delay_ms: 800)
        raise Error, "APNG requires at least two frames" unless images.length >= 2
        raise Error, "frame delay must be 1..65535 milliseconds" unless delay_ms.is_a?(Integer) && delay_ms.between?(1, 65_535)

        frames = images.map { |image| parse_png(image) }
        header, prelude = frames.first.values_at(:header, :prelude)
        unless frames.all? { |frame| frame[:header] == header && frame[:palette] == frames.first[:palette] }
          raise Error, "APNG frames need matching dimensions and color format"
        end

        width, height = header.unpack("N2")
        output = SIGNATURE + png_chunk("IHDR", header) + prelude.join + png_chunk("acTL", [frames.length, 0].pack("N2"))
        sequence = 0
        frames.each_with_index do |frame, index|
          control = [sequence, width, height, 0, 0, delay_ms, 1000, 0, 0].pack("N5n2C2")
          output << png_chunk("fcTL", control)
          sequence += 1
          frame[:data].each do |data|
            output << if index.zero?
              png_chunk("IDAT", data)
            else
              chunk = png_chunk("fdAT", [sequence].pack("N") + data)
              sequence += 1
              chunk
            end
          end
        end
        output << png_chunk("IEND", "".b)
      end

      private

      def parse_png(image)
        raise Error, "invalid PNG frame" unless image.start_with?(SIGNATURE)

        position = SIGNATURE.bytesize
        chunks = []
        while position + 12 <= image.bytesize
          length = image.byteslice(position, 4).unpack1("N")
          finish = position + length + 12
          raise Error, "invalid PNG frame" if finish > image.bytesize

          type = image.byteslice(position + 4, 4)
          data = image.byteslice(position + 8, length)
          crc = image.byteslice(finish - 4, 4).unpack1("N")
          raise Error, "invalid PNG frame checksum" unless crc == Zlib.crc32(type + data)

          chunks << [type, data]
          position = finish
          break if type == "IEND"
        end
        raise Error, "invalid PNG frame" unless position == image.bytesize && chunks.first&.first == "IHDR" &&
                                                  chunks.first.last.bytesize == 13 && chunks.last&.first == "IEND"

        first_data = chunks.index { |type, _| type == "IDAT" }
        raise Error, "PNG frame has no image data" unless first_data
        prelude = chunks[1...first_data]
        raise Error, "already animated PNG frames are unsupported" if chunks.any? { |type, _| %w[acTL fcTL fdAT].include?(type) }

        { header: chunks.first.last, prelude: prelude.map { |type, data| png_chunk(type, data) },
          palette: prelude.select { |type, _| %w[PLTE tRNS].include?(type) },
          data: chunks.filter_map { |type, data| data if type == "IDAT" } }
      end

      def png_chunk(type, data)
        [data.bytesize].pack("N") + type + data + [Zlib.crc32(type + data)].pack("N")
      end
    end
  end
end
