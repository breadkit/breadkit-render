# frozen_string_literal: true

require "rexml/document"
require "tmpdir"

RSpec.describe Breadkit::Render::SvgRenderer do
  let(:circuit) { Breadkit.load(File.expand_path("../../../breadkit/examples/01_led_button.bk.rb", __dir__)) }

  it "renders deterministic, well-formed SVG with escaped text and layers" do
    circuit.instance_variable_set(:@title, "R&D <LED>")
    svg = described_class.new.render(circuit, legend: true, show_nets: true)
    expect { REXML::Document.new(svg) }.not_to raise_error
    expect(svg).to include("R&amp;D &lt;LED&gt;", "id=\"board\"", "id=\"wires\"", "data-hole=\"a10\"")
    expect(described_class.new.render(circuit, legend: true, show_nets: true)).to eq(svg)
  end

  it "can render an empty board and every bundled board size" do
    %w[full half mini].each do |type|
      builder = Breadkit::DSL::Builder.new
      builder.instance_eval("board :#{type}", "empty.bk.rb", 1)
      svg = described_class.new.render(Breadkit::Resolver.new.call(builder.document))
      expect(REXML::Document.new(svg).root.attributes["viewBox"]).not_to be_nil
    end
  end

  it "overlays lint targets with markers and messages" do
    annotations = [{ "rule" => "Electrical/ShortCircuit", "severity" => "error", "message" => "short",
                     "targets" => { "holes" => ["a10"], "wires" => ["W1"], "components" => ["SW1"] } }]
    svg = described_class.new.render(circuit, annotations: annotations)
    expect(svg).to include("id=\"annotations\"", "#d62728", "1. short")
    expect { REXML::Document.new(svg) }.not_to raise_error
  end

  it "uses automatic wire colors and reads annotations from bklint JSON" do
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval('board :mini; wire "a1", "a2"', "wire.bk.rb", 1)
    wire_svg = described_class.new.render(Breadkit::Resolver.new.call(builder.document))
    expect(wire_svg).to include("stroke=\"#d62728\"")

    input = File.expand_path("../../../breadkit/examples/bad/short_circuit.bk.rb", __dir__)
    json = { schema_version: 1, files: [{ path: input, offenses: [{ rule: "Electrical/ShortCircuit", severity: "error",
      message: "short circuit", targets: { holes: ["a10"], wires: ["W1"] } }] }] }
    Dir.mktmpdir do |directory|
      annotations_path, output_path = File.join(directory, "lint.json"), File.join(directory, "review.svg")
      File.write(annotations_path, JSON.generate(json))
      status = Breadkit::Render::CLI.new.run([input, "--annotations", annotations_path, "-o", output_path])
      expect(status).to eq(0)
      expect(File.read(output_path)).to include("1. short circuit", "#d62728")
    end
  end

  it "renders offboard module pins and connects their wires" do
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval('board :half; offboard :UNO, "arduino_uno"; wire "UNO.D13", "a1"', "sample.bk.rb", 1)
    circuit = Breadkit::Resolver.new.call(builder.document)
    svg = described_class.new.render(circuit)

    expect(svg).to include("Arduino Uno", "UNO.D13", "id=\"offboard\"")
    expect(svg.scan("<path ").length).to eq(1)
  end

  it "maps resistor values to the expected four-band colors" do
    renderer = described_class.new
    colors = %w[#000000 #8b4513 #ff0000 #ff8c00 #ffff00 #008000 #0000ff #800080 #808080 #ffffff]
    expect(renderer.send(:resistor_bands, "220")).to eq([colors[2], colors[2], colors[1], "#d4af37"])
    expect(renderer.send(:resistor_bands, "330")).to eq([colors[3], colors[3], colors[1], "#d4af37"])
    expect(renderer.send(:resistor_bands, "10k")).to eq([colors[1], colors[0], colors[3], "#d4af37"])
  end
end

RSpec.describe Breadkit::Render::CLI do
  it "rejects output extensions that conflict with the requested format" do
    expect(described_class.new.run(["-o", "diagram.png", "-f", "svg", "input.bk.rb"]))
      .to eq(2)
  end

  it "rasterizes to PNG and JPEG when optional system backends are installed" do
    svg = Breadkit::Render::SvgRenderer.new.render(Breadkit.load(File.expand_path("../../../breadkit/examples/01_led_button.bk.rb", __dir__)))
    rasterizer = Breadkit::Render::Rasterizer.new
    expect(rasterizer.rasterize(svg, format: "png")).to start_with("\x89PNG\r\n\x1a\n".b)
    expect(rasterizer.rasterize(svg, format: "jpeg")).to start_with("\xFF\xD8".b)
  rescue Breadkit::Render::Error => e
    skip e.message
  end
end
