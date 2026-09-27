# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "zlib"

RSpec.describe "APNG output" do
  def chunk(type, data)
    [data.bytesize].pack("N") + type + data + [Zlib.crc32(type + data)].pack("N")
  end

  def png(red, width: 1)
    pixel = red ? [255, 0, 0, 255] : [0, 0, 255, 255]
    "\x89PNG\r\n\x1a\n".b + chunk("IHDR", [width, 1, 8, 6, 0, 0, 0].pack("NNC5")) +
      chunk("IDAT", Zlib::Deflate.deflate([0, *Array.new(width) { pixel }.flatten].pack("C*"))) + chunk("IEND", "".b)
  end

  def chunks(bytes)
    position = 8
    items = []
    while position < bytes.bytesize
      length = bytes.byteslice(position, 4).unpack1("N")
      type = bytes.byteslice(position + 4, 4)
      data = bytes.byteslice(position + 8, length)
      crc = bytes.byteslice(position + 8 + length, 4).unpack1("N")
      expect(crc).to eq(Zlib.crc32(type + data))
      items << [type, data]
      position += length + 12
    end
    items
  end

  it "encodes two valid full-frame PNG images with ordered animation chunks" do
    output = Breadkit::Render::ApngEncoder.new.encode([png(true), png(false)], delay_ms: 750)
    expect(output).to start_with("\x89PNG\r\n\x1a\n".b)
    items = chunks(output)
    expect(items.map(&:first)).to eq(%w[IHDR acTL fcTL IDAT fcTL fdAT IEND])
    expect(items[1][1].unpack("N2")).to eq([2, 0])
    expect(items[2][1].unpack("N5n2C2")).to eq([0, 1, 1, 0, 0, 750, 1000, 0, 0])
    expect(items[4][1].unpack("N5n2C2").first).to eq(1)
    expect(items[5][1].unpack1("N")).to eq(2)
    expect(Zlib::Inflate.inflate(items[3][1])).to eq([0, 255, 0, 0, 255].pack("C*"))
    expect(Zlib::Inflate.inflate(items[5][1].byteslice(4..))).to eq([0, 0, 0, 255, 255].pack("C*"))
  end

  it "rejects invalid frame timing and mismatched frame dimensions" do
    encoder = Breadkit::Render::ApngEncoder.new
    expect { encoder.encode([png(true), png(false)], delay_ms: 0) }.to raise_error(Breadkit::Render::Error, /delay/)
    expect { encoder.encode([png(true), png(false, width: 2)]) }.to raise_error(Breadkit::Render::Error, /matching/)
  end

  it "animates assembly steps and rejects ambiguous single-frame circuits" do
    skip "PNG backend unavailable" unless %w[rsvg vips magick].any? { |name| Breadkit::Render::Rasterizer.new.send(:supports?, name, "png") }

    Dir.mktmpdir do |directory|
      input = File.join(directory, "steps.bk.rb")
      output = File.join(directory, "steps.apng")
      File.write(input, "board :mini\nstep 1 do\n resistor :R1, '330', pins: %w[a1 a3]\nend\nstep 2 do\n wire 'a5', 'b7'\nend\n")
      expect(Breadkit::Render::CLI.new.run([input, "-o", output, "--frame-delay", "500"])).to eq(0)
      items = chunks(File.binread(output))
      expect(items.find { |type, _| type == "acTL" }[1].unpack("N2")).to eq([2, 0])
      expect(items.select { |type, _| type == "fcTL" }.map { |_, data| data.unpack1("N") }).to eq([0, 1])

      File.write(input, "board :mini\n")
      expect { expect(Breadkit::Render::CLI.new.run([input, "-o", output])).to eq(2) }
        .to output(/at least two/).to_stderr
    end
  end

  it "animates open and closed switch states" do
    skip "PNG backend unavailable" unless %w[rsvg vips magick].any? { |name| Breadkit::Render::Rasterizer.new.send(:supports?, name, "png") }

    Dir.mktmpdir do |directory|
      input = File.join(directory, "switch.bk.rb")
      output = File.join(directory, "switch.apng")
      File.write(input, 'board :mini; button :SW1, at: "e5"')
      expect(Breadkit::Render::CLI.new.run([input, "--animate", "states", "-o", output])).to eq(0)
      items = chunks(File.binread(output))
      expect(items.find { |type, _| type == "acTL" }[1].unpack1("N")).to eq(2)
      expect(items.count { |type, _| type == "fcTL" }).to eq(2)
      open_pixels = Zlib::Inflate.inflate(items.filter_map { |type, data| data if type == "IDAT" }.join)
      closed_pixels = Zlib::Inflate.inflate(items.filter_map { |type, data| data.byteslice(4..) if type == "fdAT" }.join)
      expect(closed_pixels).not_to eq(open_pixels)
      expect { expect(Breadkit::Render::CLI.new.run([input, "--state", "SW1", "-o", output])).to eq(2) }
        .to output(/cannot select a single/).to_stderr
    end
  end
end
