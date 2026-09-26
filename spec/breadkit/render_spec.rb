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

  it "adds a bounded legend with each net name and representative wire color" do
    svg = described_class.new.render(circuit, legend: true)
    document = REXML::Document.new(svg)
    view_box = document.root.attributes["viewBox"].split.map(&:to_f)
    legend = document.root.elements["g[@id='legend']"]

    expect(view_box).to have_attributes(length: 4)
    expect(legend.elements.to_a("text").map(&:text)).to include("VCC", "GND", "N1", "N2")
    expect(legend.elements.to_a("line").map { |item| item.attributes["stroke"] }).to include("red", "black")
    expect(legend.elements.to_a("text").all? { |item| item.attributes["y"].to_f <= view_box[1] + view_box[3] }).to be(true)
  end

  it "omits isolated offboard pins from the legend" do
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval('board :half; offboard :UNO, "arduino_uno"; wire "UNO.D13", "g10"', "offboard.bk.rb", 1)
    diagram = Breadkit::Resolver.new.call(builder.document)
    legend = REXML::Document.new(described_class.new.render(diagram, legend: true)).root.elements["g[@id='legend']"]

    expect(legend.elements.to_a("line").length).to eq(diagram.nets.count { |net| net.members.length > 1 || net.holes.any? })
    expect(legend.elements.to_a("line").length).to be < diagram.nets.length
  end

  it "can render an empty board and every bundled board size" do
    %w[full half mini].each do |type|
      builder = Breadkit::DSL::Builder.new
      builder.instance_eval("board :#{type}", "empty.bk.rb", 1)
      svg = described_class.new.render(Breadkit::Resolver.new.call(builder.document))
      expect(REXML::Document.new(svg).root.attributes["viewBox"]).not_to be_nil
    end
  end

  it "uses board-defined rows and ravine labels" do
    definition = Breadkit::BoardDef.new("id" => "custom", "terminal" => {
      "columns" => 2, "rows" => %w[a b g h], "groups" => [%w[a b], %w[g h]], "ravine_between" => %w[b g]
    })
    diagram = Breadkit::Circuit.new(title: nil, board: Breadkit::Board.new(definition), components: {}, wires: [],
                                    supplies: [], labels: [], expectations: [], lint_disables: [], diagnostics: [])
    document = REXML::Document.new(described_class.new.render(diagram))
    labels = REXML::XPath.first(document, "//g[@id='labels']").elements.to_a("text").map(&:text)

    expect(labels).to include("a", "b", "g", "h")
    expect(labels).not_to include("e", "f")
    expect(REXML::XPath.first(document, "//g[@id='board']").elements.to_a("rect").length).to eq(2)
  end

  it "renders custom row and rail wire endpoints through the CLI" do
    Dir.mktmpdir do |directory|
      definition = {
        "id" => "custom", "terminal" => {
          "columns" => 3, "rows" => %w[u v w x], "groups" => [%w[u v], %w[w x]], "ravine_between" => %w[v w]
        },
        "rails" => [
          { "id" => "TOPP", "side" => "top", "order" => 0, "polarity" => "+" },
          { "id" => "TOPN", "side" => "top", "order" => 1, "polarity" => "-" },
          { "id" => "PWR", "side" => "bottom", "order" => 0, "polarity" => "+" },
          { "id" => "RET", "side" => "bottom", "order" => 1, "polarity" => "-" }
        ],
        "rail_layout" => { "holes" => 3, "group_size" => 3, "start_column" => 1, "segments" => [[1, 3]] }
      }
      File.write(File.join(directory, "custom.yml"), YAML.dump(definition))
      input, output = File.join(directory, "custom.bk.rb"), File.join(directory, "custom.svg")
      File.write(input, 'use_boards "custom.yml"; board :custom; wire "u1", "PWR1"; wire "v2", "RET1"')

      expect(Breadkit::Render::CLI.new.run([input, "--rail-pattern", "+--+", "-o", output])).to eq(0)
      document = REXML::Document.new(File.read(output))
      wires = REXML::XPath.first(document, "//g[@id='wires']").elements.to_a("path").select { |wire| wire.attributes["data-ref"] }
      expect(wires.map { |wire| wire.attributes["data-ref"] }).to eq(%w[W1 W2])
      expect(wires.map { |wire| wire.attributes["d"].split.last }).to eq(%w[80.00 70.00])
      expect(document.root.attributes["data-rail-pattern"]).to eq("+--+")
      holes = REXML::XPath.first(document, "//g[@id='holes']").elements.to_a("circle").map { |hole| hole.attributes["data-hole"] }
      expect(holes).to include("u1", "PWR1", "RET1")
    end
  end

  it "maps rail connections to each selected polarity pattern" do
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval('board :half; wire "a1", "T+1"; wire "a2", "B+1"', "rails.bk.rb", 1)
    circuit = Breadkit::Resolver.new.call(builder.document)
    expected_y = {
      "+--+" => ["-30.00", "140.00"],
      "+-+-" => ["-20.00", "140.00"],
      "-+-+" => ["-30.00", "130.00"],
      "-++-" => ["-20.00", "130.00"]
    }

    expected_y.each do |pattern, (top_y, bottom_y)|
      svg = described_class.new.render(circuit, orientation: "landscape", rail_pattern: pattern)
      document = REXML::Document.new(svg)
      wires = document.root.elements["g[@id='wires']"]
      endpoints = %w[W1 W2].map do |id|
        d = wires.elements["path[@data-ref='#{id}']"].attributes["d"]
        d.split.last
      end

      expect(document.root.attributes["data-rail-pattern"]).to eq(pattern)
      expect(endpoints).to eq([top_y, bottom_y])
      next unless pattern == "+--+"

      positive_rail = document.root.elements["g[@id='board']"].elements.to_a("rect").find do |rect|
        rect.attributes["data-rail"] == "T+"
      end
      top_inner_mark = document.root.elements["g[@id='labels']"].elements.to_a("text").find do |label|
        label.attributes["data-rail"] == "T+"
      end
      expect(positive_rail.attributes["fill"]).to eq("#cf5955")
      expect(top_inner_mark.text).to eq("-")
    end
  end

  it "rejects unsupported rail polarity patterns" do
    expect { described_class.new.render(circuit, rail_pattern: "+---") }
      .to raise_error(ArgumentError, /rail pattern/)
  end

  it "keeps split rail segments mapped to the selected polarity" do
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval('board :full, split_rails: true; wire "a1", "T+50"', "split-rails.bk.rb", 1)
    circuit = Breadkit::Resolver.new.call(builder.document)
    document = REXML::Document.new(described_class.new.render(circuit, orientation: "landscape", rail_pattern: "+--+"))

    wire = document.root.elements["g[@id='wires']/path[@data-ref='W1']"]
    marks = document.root.elements["g[@id='labels']"].elements.to_a("text").count do |label|
      label.attributes["data-rail"] == "T+"
    end
    expect(wire.attributes["d"].split.last).to eq("-30.00")
    expect(marks).to eq(2)
  end

  it "overlays lint targets with markers and messages" do
    annotations = [{ "rule" => "Electrical/ShortCircuit", "severity" => "error", "message" => "short",
                     "targets" => { "holes" => ["a10"], "wires" => ["W1"], "components" => ["SW1"] } }]
    svg = described_class.new.render(circuit, annotations: annotations)
    expect(svg).to include("id=\"annotations\"", "#d62728", "1. short")
    expect { REXML::Document.new(svg) }.not_to raise_error
  end

  it "places numbered badges at targets and wraps long legend messages" do
    message = "Check the connected power net and follow every marked hole before applying power. " * 4
    annotations = [{ "severity" => "error", "message" => message, "targets" => { "nets" => ["VCC"] } },
                   { "severity" => "warning", "message" => "Check the switch", "targets" => { "holes" => ["a10"] } }]
    document = REXML::Document.new(described_class.new.render(circuit, annotations: annotations))
    badges = REXML::XPath.first(document, "//g[@id='annotations']").elements.to_a("text")
    first_hole = circuit.board.hole(circuit.nets.find { |net| net.name == "VCC" }.holes.first)
    second_hole = circuit.board.hole("a10")
    legend_lines = document.root.elements["g[@id='legend']"].elements.to_a("text")
    view_height = document.root.attributes["viewBox"].split.last.to_f

    expect(badges.map(&:text)).to eq(%w[1 2])
    expect(badges[0].attributes["x"].to_f).to be_within(0.01).of(first_hole.x * 10 + 7)
    expect(badges[1].attributes["x"].to_f).to be_within(0.01).of(second_hole.x * 10 + 7)
    expect(legend_lines.length).to be > 3
    expect(legend_lines.all? { |line| line.attributes["y"].to_f < view_height }).to be(true)
    expect(document.root.elements["g[@id='legend']"].elements["rect"].attributes["fill"]).to eq("#f2f5f2")
  end

  it "uses state-specific nets for annotation targets and wraps wide glyphs" do
    annotations = [{ "state" => "SW1", "message" => "MW😀漢" * 35, "targets" => { "nets" => ["VCC"] } }]
    document = REXML::Document.new(described_class.new.render(circuit, annotations: annotations))
    markers = REXML::XPath.first(document, "//g[@id='annotations']").elements.to_a("circle")
    target = circuit.board.hole("a12")
    legend = document.root.elements["g[@id='legend']"]

    expect(markers.any? do |circle|
      (circle.attributes["cx"].to_f - target.x * 10).abs < 0.01 &&
        (circle.attributes["cy"].to_f - (circuit.board.height - 1 - target.y) * 10).abs < 0.01
    end).to be(true)
    expect(legend.elements.to_a("text").length).to be > 3
    expect(legend.elements.to_a("text").all? { |line| line.text.length < 35 }).to be(true)
  end

  it "marks net targets made only of offboard pins" do
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval('board :half; offboard :A, "arduino_uno"; offboard :B, "arduino_uno"; wire "A.D13", "B.D13"',
                          "offboard.bk.rb", 1)
    diagram = Breadkit::Resolver.new.call(builder.document)
    net = diagram.nets.find { |item| item.members.include?("W1") }
    svg = described_class.new.render(diagram, annotations: [{ "targets" => { "nets" => [net.name] } }])

    expect(net.holes).to be_empty
    expect(REXML::XPath.first(REXML::Document.new(svg), "//g[@id='annotations']/text").text).to eq("1")
  end

  it "uses automatic wire colors and reads annotations from bklint JSON" do
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval('board :mini; wire "a1", "a2"', "wire.bk.rb", 1)
    wire_svg = described_class.new.render(Breadkit::Resolver.new.call(builder.document))
    expect(wire_svg).to include("stroke=\"#d62728\"")

    input = File.expand_path("../../../breadkit/examples/bad/short_circuit.bk.rb", __dir__)
    json = { schema_version: 1, files: [{ path: input, offenses: [{ rule: "Electrical/ShortCircuit", severity: "error",
      message: "short circuit Ω", targets: { holes: ["a10"], wires: ["W1"] } }] }] }
    Dir.mktmpdir do |directory|
      annotations_path, output_path = File.join(directory, "lint.json"), File.join(directory, "review.svg")
      File.write(annotations_path, JSON.generate(json))
      original_encoding = Encoding.default_external
      begin
        Encoding.default_external = Encoding::US_ASCII
        status = Breadkit::Render::CLI.new.run([input, "--annotations", annotations_path, "-o", output_path])
      ensure
        Encoding.default_external = original_encoding
      end
      expect(status).to eq(0)
      expect(File.read(output_path)).to include("1. short circuit Ω", "#d62728")
    end
  end

  it "renders offboard module pins and connects their wires" do
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval('board :half; offboard :UNO, "arduino_uno"; wire "UNO.D13", "g10", route: :edge; wire "UNO.D12", "g12", route: :edge', "sample.bk.rb", 1)
    circuit = Breadkit::Resolver.new.call(builder.document)
    svg = described_class.new.render(circuit)
    paths = REXML::XPath.first(REXML::Document.new(svg), "//g[@id='wires']").elements.to_a("path")

    expect(svg).to include("Arduino Uno", "UNO.D13", "id=\"offboard\"")
    expect(paths.map { |path| path.attributes["data-ref"] }).to eq([nil, nil, "W1", "W2"])
    expect(paths.last(2).map { |path| path.attributes["d"].split(" L ")[1].split.last }.uniq.length).to eq(2)
  end

  it "renders a custom module as a sized board with visible pin pads" do
    Dir.mktmpdir do |directory|
      definition = {
        "id" => "test_oled", "placement" => "footprint",
        "pins" => [{ "num" => 1, "name" => "GND" }, { "num" => 2, "name" => "SDA" }],
        "footprint" => { "1" => [0, 0], "2" => [1, 0] },
        "render" => { "shape" => "module", "label" => "OLED", "size_mm" => [27, 20], "body_offset_mm" => [0, 8] }
      }
      File.write(File.join(directory, "test_oled.yml"), YAML.dump(definition))

      builder = Breadkit::DSL::Builder.new(base_dir: directory)
      builder.instance_eval('board :half; use_parts "test_oled.yml"; part :OLED, :test_oled, at: "c10"', "module.bk.rb", 1)
      svg = described_class.new.render(Breadkit::Resolver.new.call(builder.document), orientation: "landscape")
      document = REXML::Document.new(svg)
      module_group = document.root.elements["g[@id='components']"].elements["g[@data-ref='OLED']"]
      body = module_group.elements["rect[@data-ref='OLED']"]
      pin = module_group.elements.to_a("circle").find { |item| item.attributes["data-pin"] == "OLED.GND" }
      left, top, view_width, view_height = document.root.attributes["viewBox"].split.map(&:to_f)

      expect([body.attributes["width"], body.attributes["height"]]).to eq(%w[106.30 78.74])
      expect(Float(body.attributes["y"]) + Float(body.attributes["height"]) - Float(pin.attributes["cy"]))
        .to be_within(0.01).of(7.87)
      expect(Float(body.attributes["x"])).to be >= left
      expect(Float(body.attributes["y"])).to be >= top
      expect(Float(body.attributes["x"]) + Float(body.attributes["width"])).to be <= left + view_width
      expect(Float(body.attributes["y"]) + Float(body.attributes["height"])).to be <= top + view_height
      expect(module_group.elements.to_a("text").map(&:text)).to include("OLED")
      expect(module_group.elements.to_a("circle").map { |pin| pin.attributes["data-pin"] }).to include("OLED.GND", "OLED.SDA")
    end
  end

  it "keeps compact module labels clear of their pin pads" do
    input = File.expand_path("../../../breadkit/examples/05_sensor_demo.bk.rb", __dir__)
    circuit = Breadkit.load(input)

    %w[portrait landscape].each do |orientation|
      document = REXML::Document.new(described_class.new.render(circuit, orientation: orientation))
      axis = orientation == "portrait" ? "x" : "y"
      %w[IR_RX IR_TX].each do |ref|
        group = REXML::XPath.first(document, "//g[@data-ref='#{ref}']")
        label = group.elements.to_a("text").find { |item| %w[Receiver Emitter].include?(item.text) }
        pin_positions = group.elements.to_a("circle").filter_map do |item|
          item.attributes["c#{axis}"].to_f if item.attributes["data-pin"]
        end
        expect(pin_positions.map { |position| (position - label.attributes[axis].to_f).abs }.min).to be > 5.3
      end

      pico = REXML::XPath.first(document, "//g[@data-ref='PICO']")
      body = pico.elements["rect"]
      label_x = pico.elements.to_a("text").find { |item| item.text == "RP2040" }.attributes["x"].to_f
      expect(label_x).to be_within(0.01).of(body.attributes["x"].to_f + body.attributes["width"].to_f / 2)
    end
  end

  it "maps resistor values to the expected four-band colors" do
    renderer = described_class.new
    colors = %w[#000000 #8b4513 #ff0000 #ff8c00 #ffff00 #008000 #0000ff #800080 #808080 #ffffff]
    expect(renderer.send(:resistor_bands, "220")).to eq([colors[2], colors[2], colors[1], "#d4af37"])
    expect(renderer.send(:resistor_bands, "330")).to eq([colors[3], colors[3], colors[1], "#d4af37"])
    expect(renderer.send(:resistor_bands, "10k")).to eq([colors[1], colors[0], colors[3], "#d4af37"])
    expect(renderer.send(:resistor_bands, "1")).to eq([colors[1], colors[0], "#d4af37", "#d4af37"])
    expect(renderer.send(:resistor_bands, "4.7")).to eq([colors[4], colors[7], "#d4af37", "#d4af37"])
    expect(renderer.send(:resistor_bands, "0.47")).to eq([colors[4], colors[7], "#c0c0c0", "#d4af37"])
    expect(renderer.send(:resistor_bands, "995")).to eq([colors[1], colors[0], colors[2], "#d4af37"])
    expect(renderer.send(:resistor_bands, "995", bands: 5)).to eq([colors[9], colors[9], colors[5], colors[0], colors[1]])

    builder = Breadkit::DSL::Builder.new
    builder.instance_eval('board :half; resistor :R1, "995", pins: %w[a1 a5], bands: 5', "resistor.bk.rb", 1)
    diagram = Breadkit::Resolver.new.call(builder.document)
    body = REXML::XPath.first(REXML::Document.new(renderer.render(diagram)), "//g[@data-ref='R1']")
    expect(body.elements.to_a("rect").drop(1).map { |band| band.attributes["fill"] })
      .to eq([colors[9], colors[9], colors[5], colors[0], colors[1]])
  end

  it "matches empty-board and example SVG snapshots" do
    %w[full half mini].each do |type|
      builder = Breadkit::DSL::Builder.new
      builder.instance_eval("board :#{type}", "empty.bk.rb", 1)
      circuit = Breadkit::Resolver.new.call(builder.document)
      expect_svg_snapshot("empty_#{type}", described_class.new.render(circuit))
    end

    %w[01_led_button 02_555_blinker].each do |name|
      path = File.expand_path("../../../breadkit/examples/#{name}.bk.rb", __dir__)
      expect_svg_snapshot(name, described_class.new.render(Breadkit.load(path)))
    end
  end

  it "marks occupied holes separately from connected strips" do
    document = REXML::Document.new(described_class.new.render(circuit))
    occupied = REXML::XPath.first(document, "//circle[@data-hole='a12']")
    connected = REXML::XPath.first(document, "//circle[@data-hole='b12']")

    expect(occupied.attributes["data-occupied"]).to eq("true")
    expect(connected.attributes["data-connected"]).to eq("true")
    expect(connected.attributes["data-occupied"]).to be_nil
    expect(occupied.attributes["fill"]).not_to eq(connected.attributes["fill"])
  end

  it "uses theme colors and supports named or hexadecimal LED colors" do
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval("board :half\nresistor :R1, '330', pins: %w[a1 a5]\nled :D1, color: :purple, anode: 'b7', cathode: 'b8'",
                          "colors.bk.rb", 1)
    diagram = Breadkit::Resolver.new.call(builder.document)
    document = REXML::Document.new(described_class.new.render(diagram, theme: "dark"))
    resistor_body = REXML::XPath.first(document, "//g[@data-ref='R1']/rect")
    led_body = REXML::XPath.first(document, "//g[@data-ref='D1']/circle")

    expect(resistor_body.attributes["fill"]).to eq("#6b6248")
    expect(led_body.attributes["fill"]).to eq("purple")
    diagram.components["D1"].attrs[:color] = "#6d5af0"
    expect(described_class.new.render(diagram)).to include('fill="#6d5af0"')
    diagram.components["D1"].attrs[:color] = :rebeccapurple
    expect(described_class.new.render(diagram)).to include('fill="rebeccapurple"')
    diagram.components["D1"].attrs[:color] = :notacolor
    expect { described_class.new.render(diagram) }.to raise_error(Breadkit::Render::Error, /invalid LED color: notacolor/)
  end

  it "separates overlapping offboard rail wires and reuses clear tracks" do
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval('board :half; offboard :UNO, "arduino_uno"; offboard :UNO2, "arduino_uno", at: "a30"; wire "UNO.D13", "B+1", route: :edge; wire "UNO.D12", "B+2", route: :edge; wire "UNO.D11", "B+3", route: :edge; wire "UNO2.D13", "B+25", route: :edge',
                          "offboard_rails.bk.rb", 1)
    diagram = Breadkit::Resolver.new.call(builder.document)
    renderer = described_class.new
    renderer.render(diagram)
    tracks = renderer.send(:offboard_rail_tracks, "left", diagram.board.hole("B+1").y)

    expect(tracks.keys.map(&:id).sort).to eq(%w[W1 W2 W3 W4])
    expect(tracks.values_at(*diagram.wires.first(3)).uniq.length).to eq(3)
    expect(tracks[diagram.wires.last]).to eq(0)
  end

  it "assigns bounded net colors and a separate negative-voltage color" do
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval('board :half; supply :NEG, voltage: -5, plus: "B+1", minus: "B-1"; net :GND, at: "B-1"; wire "a1", "B+1"',
                          "negative.bk.rb", 1)
    diagram = Breadkit::Resolver.new.call(builder.document)
    svg = described_class.new.render(diagram, color_by: "net")
    wire = REXML::XPath.first(REXML::Document.new(svg), "//g[@id='wires']/path[@data-ref='W1']")

    expect(wire.attributes["stroke"]).to eq("#315ea8")
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval('board :half; wire "a1", "a2"', "unpowered.bk.rb", 1)
    svg = described_class.new.render(Breadkit::Resolver.new.call(builder.document), color_by: "net")
    wire = REXML::XPath.first(REXML::Document.new(svg), "//g[@id='wires']/path[@data-ref='W1']")
    expect(described_class::PALETTE).to include(wire.attributes["stroke"])
  end
end

RSpec.describe Breadkit::Render::CLI do
  it "treats unknown diagnostic severities as errors" do
    input = File.expand_path("../../../breadkit/examples/01_led_button.bk.rb", __dir__)
    diagram = Breadkit.load(input)
    diagram.diagnostics << Breadkit::Diagnostic.new(code: "unknown", severity: nil, message: "bad input", location: nil, targets: [])
    allow(Breadkit).to receive(:load).and_return(diagram)

    Dir.mktmpdir do |directory|
      output = File.join(directory, "diagram.svg")
      expect(described_class.new.run([input, "-o", output])).to eq(1)
      expect(File.exist?(output)).to be(false)
    end
  end

  it "rejects PNG backgrounds and binary output to a terminal" do
    input = File.expand_path("../../../breadkit/examples/01_led_button.bk.rb", __dir__)
    expect(described_class.new.run([input, "--format", "png", "--background", "red"])).to eq(2)
    allow($stdout).to receive(:tty?).and_return(true)
    expect(described_class.new.run([input, "--format", "png"])).to eq(2)
  end

  it "writes a static SVG without scripts or layer controls" do
    Dir.mktmpdir do |directory|
      input, output = File.join(directory, "layers.bk.rb"), File.join(directory, "layers.svg")
      File.write(input, 'board :half; wire "a1", "a2", layer: "Power"')
      expect(described_class.new.run([input, "--static", "-o", output])).to eq(0)
      svg = File.read(output)
      expect(svg).not_to include("<script", "data-layer-button")
    end
  end

  it "passes the selected rail pattern through to SVG output" do
    input = File.expand_path("../../../breadkit/examples/01_led_button.bk.rb", __dir__)
    Dir.mktmpdir do |directory|
      Breadkit::Render::SvgRenderer::RAIL_PATTERNS.each do |pattern|
        output = File.join(directory, "rails.svg")
        status = described_class.new.run([input, "--rail-pattern", pattern, "-o", output])

        expect(status).to eq(0)
        expect(REXML::Document.new(File.read(output)).root.attributes["data-rail-pattern"]).to eq(pattern)
      end
    end
  end

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

  it "validates raster options before selecting a backend" do
    rasterizer = Breadkit::Render::Rasterizer.new
    expect { rasterizer.rasterize("", format: "gif") }.to raise_error(Breadkit::Render::Error, /unsupported raster format/)
    expect { rasterizer.rasterize("", format: "png", scale: 0) }.to raise_error(Breadkit::Render::Error, /scale/)
    expect { rasterizer.rasterize("", format: "png", scale: Float::INFINITY) }.to raise_error(Breadkit::Render::Error, /scale/)
    expect { rasterizer.rasterize("", format: "png", quality: 101) }.to raise_error(Breadkit::Render::Error, /quality/)
    expect { rasterizer.rasterize("", format: "png", backend: "unknown") }.to raise_error(Breadkit::Render::Error, /unsupported raster backend/)
  end

  it "parses white and hex JPEG backgrounds for libvips" do
    rasterizer = Breadkit::Render::Rasterizer.new
    expect(rasterizer.send(:color, "white")).to eq([255, 255, 255])
    expect(rasterizer.send(:color, "purple")).to eq([128, 0, 128])
    expect(rasterizer.send(:color, "#123")).to eq([17, 34, 51])
    expect(rasterizer.send(:color, "#123456")).to eq([18, 52, 86])
    expect { rasterizer.send(:color, "not a color") }.to raise_error(Breadkit::Render::Error, /background color/)
  end

  it "produces valid raster files through each available backend" do
    rasterizer = Breadkit::Render::Rasterizer.new
    svg = '<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"/>'
    signatures = { "png" => "\x89PNG\r\n\x1a\n".b, "jpeg" => "\xFF\xD8".b }

    [["rsvg", "png"], ["vips", "png"], ["vips", "jpeg"], ["magick", "png"], ["magick", "jpeg"]].each do |backend, format|
      next unless rasterizer.send(:supports?, backend, format)

      output = rasterizer.rasterize(svg, format: format, backend: backend)
      expect(output).to start_with(signatures.fetch(format))
    end

    if rasterizer.send(:supports?, "vips", "jpeg")
      jpeg = rasterizer.rasterize(svg, format: "jpeg", backend: "vips")
      expect(Vips::Image.jpegload_buffer(jpeg).getpoint(0, 0)).to eq([255.0, 255.0, 255.0])
    end
  end

  it "rasterizes ImageMagick at source resolution with transparency or chosen background" do
    rasterizer = Breadkit::Render::Rasterizer.new
    skip "ImageMagick unavailable" unless rasterizer.send(:supports?, "magick", "png")

    svg = '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="10"><circle cx="10" cy="5" r="2" fill="red"/></svg>'
    png = rasterizer.rasterize(svg, format: "png", scale: 2, backend: "magick")
    pixel, stderr, status = Open3.capture3(rasterizer.send(:magick_command), "png:-", "-format", "%[pixel:p{0,0}]", "info:",
                                           stdin_data: png, binmode: true)

    expect(png.byteslice(16, 8).unpack("N2")).to eq([40, 20])
    expect(status.success?).to be(true), stderr
    expect(pixel).to match(/(?:,0\)|none)/i)

    jpeg = rasterizer.rasterize('<svg xmlns="http://www.w3.org/2000/svg" width="20" height="10"/>',
                                format: "jpeg", scale: 2, background: "#123456", backend: "magick")
    pixel, = Open3.capture3(rasterizer.send(:magick_command), "jpeg:-", "-format", "%[pixel:p{0,0}]", "info:",
                            stdin_data: jpeg, binmode: true)
    expect(pixel).to match(/srgb\(18,52,8[4-9]\)/)
  end

  it "finds Windows executables through PATHEXT and avoids convert" do
    rasterizer = Breadkit::Render::Rasterizer.new
    Dir.mktmpdir do |directory|
      command = File.join(directory, "magick.EXE")
      File.write(command, "")
      File.chmod(0o755, command)
      old_path, old_pathext = ENV.values_at("PATH", "PATHEXT")
      begin
        ENV["PATH"], ENV["PATHEXT"] = directory, ".EXE;.BAT"
        allow(RbConfig::CONFIG).to receive(:[]).with("host_os").and_return("mingw")
        expect(rasterizer.send(:executable, "magick")).to eq(command)
        expect(rasterizer.send(:magick_command)).to eq(command)
        File.rename(command, File.join(directory, "convert.EXE"))
        expect(rasterizer.send(:magick_command)).to be_nil
      ensure
        ENV["PATH"], ENV["PATHEXT"] = old_path, old_pathext
      end
    end
  end
end
