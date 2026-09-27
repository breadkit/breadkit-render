# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "rexml/xpath"
require "tmpdir"

RSpec.describe Breadkit::Render::SchematicRenderer do
  let(:source) do
    <<~RUBY
      board :mini
      supply :USB, voltage: 5, plus: "a1", minus: "a5"
      net :VCC, at: "a1"
      net :GND, at: "a5"
      resistor :R1, "330", pins: %w[b1 b3]
      led :D1, anode: "a3", cathode: "b5"
    RUBY
  end

  def load_source(text)
    Dir.mktmpdir do |directory|
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, text)
      yield Breadkit.load(path), path, directory
    end
  end

  it "draws each part once with a symbol and explicit terminal wires to its resolved nets" do
    load_source(source) do |circuit, _path, _directory|
      document = REXML::Document.new(described_class.new.render(circuit, theme: "dark"))
      expect(document.root.attributes["data-view"]).to eq("schematic")
      expect(REXML::XPath.match(document, "//g[@id='devices']/g[@data-ref]").map { |item| item.attributes["data-ref"] })
        .to eq(%w[USB R1 D1])
      expect(REXML::XPath.match(document, "//g[@id='nets']/path[@data-net]").map { |item| item.attributes["data-net"] })
        .to match_array(circuit.nets.map(&:name))
      expect(REXML::XPath.match(document, "//g[@id='devices']/g[@data-symbol]").map { |item| item.attributes["data-symbol"] })
        .to eq(%w[voltage-source resistor led])
      %w[USB.+ USB.- R1.1 R1.2 D1.anode D1.cathode].each do |terminal|
        path = REXML::XPath.first(document, "//path[@data-terminal='#{terminal}']")
        expect(path.attributes["data-net"]).to eq(circuit.net_of(terminal).name)
      end
      expect(document.to_s).to include("VCC", "GND", "330", "5 V")
      expect(REXML::XPath.first(document, "//text[@data-net-label='GND']").attributes["text-anchor"]).to eq("end")
      expect(REXML::XPath.match(document, "//g[@id='devices']/g[@data-ref='R1']").length).to eq(1)
    end
  end

  it "renders a named multi-board circuit and v2 JSON IR through the CLI" do
    load_source(<<~RUBY) do |circuit, path, directory|
      board :mini, as: :B1
      board :mini, as: :B2
      supply :BAT, voltage: 5, plus: "B1.a1", minus: "B2.b5"
      resistor :R1, "330", pins: %w[B1.b1 B1.a3]
      led :D1, anode: "B2.a3", cathode: "B2.a5"
      wire "B1.b3", "B2.b3"
    RUBY
      output = File.join(directory, "schematic.svg")
      expect(Breadkit::Render::CLI.new.run([path, "--view", "schematic", "--theme", "dark", "-o", output])).to eq(0)
      document = REXML::Document.new(File.read(output))
      expect(document.root.attributes["data-view"]).to eq("schematic")
      expect(REXML::XPath.match(document, "//path[@data-terminal]").length).to eq(6)
      expect(REXML::XPath.first(document, "//path[@data-terminal='R1.2']").attributes["data-net"])
        .to eq(circuit.net_of("D1.anode").name)
      json = File.join(directory, "circuit.json")
      File.write(json, JSON.pretty_generate(circuit.to_ir))
      expect(Breadkit::Render::CLI.new.run([json, "--view", "schematic", "-o", output])).to eq(0)
      expect(REXML::Document.new(File.read(output)).root.attributes["data-view"]).to eq("schematic")
    end
  end

  it "shows every resolved pin of a multi-pin IC and offboard module once" do
    load_source(<<~RUBY) do |circuit, path, directory|
      board :half
      supply :USB, voltage: 5, plus: "a1", minus: "a3"
      ic :U1, "NE555", at: "e20"
      offboard :UNO, :arduino_uno
      wire "U1.8", "b1"
      wire "U1.1", "b3"
      wire "UNO.D13", "U1.3"
    RUBY
      output = File.join(directory, "schematic.svg")
      expect(Breadkit::Render::CLI.new.run([path, "--view", "schematic", "-o", output])).to eq(0)
      document = REXML::Document.new(File.read(output))
      expect(REXML::XPath.match(document, "//g[@data-ref='U1'][@data-symbol='ic']").length).to eq(1)
      expect(REXML::XPath.match(document, "//g[@data-ref='UNO'][@data-symbol='module']").length).to eq(1)
      %w[U1 UNO].each do |ref|
        circuit.components.fetch(ref).pins.each_key do |pin|
          terminal = "#{ref}.#{pin}"
          stubs = REXML::XPath.match(document, "//path[@data-terminal='#{terminal}']")
          expect(stubs.length).to eq(1)
          expect(stubs.first.attributes["data-net"]).to eq(circuit.net_of(terminal).name)
        end
      end
      expect(REXML::XPath.first(document, "//text[@data-pin-label='U1.VCC']").text).to eq("VCC")
      expect(REXML::XPath.first(document, "//text[@data-pin-net='UNO.D13']").text)
        .to eq(circuit.net_of("UNO.D13").name)
      expect(REXML::XPath.first(document, "//text[@data-pin-net='U1.OUT']").text)
        .to eq(circuit.net_of("UNO.D13").name)
    end
  end

  it "rejects breadboard-only controls" do
    load_source(source) do |_circuit, path, directory|
      output = File.join(directory, "schematic.svg")
      expect { expect(Breadkit::Render::CLI.new.run([path, "--view", "schematic", "--rail-pattern", "+--+", "-o", output])).to eq(2) }
        .to output(/--rail-pattern is unavailable in schematic view/).to_stderr
    end
  end

  it "omits empty bus rows and labels for isolated pins while retaining resolved net data" do
    load_source(<<~RUBY) do |circuit, _path, _directory|
      board :mini
      offboard :UNO, :arduino_uno
      resistor :R1, "330", pins: %w[a1 a3]
      wire "UNO.D13", "b1"
    RUBY
      document = REXML::Document.new(described_class.new.render(circuit))
      buses = REXML::XPath.match(document, "//g[@id='nets']/path[@data-net]")
      expect(buses.map { |bus| bus.attributes["data-net"] }).to eq([circuit.net_of("R1.1").name,
                                                              circuit.net_of("R1.2").name])
      expect(REXML::XPath.first(document, "//text[@data-pin-net='UNO.D0']")).to be_nil
      isolated = REXML::XPath.first(document, "//path[@data-terminal='UNO.D0']")
      expect(isolated.attributes["data-net"]).to eq(circuit.net_of("UNO.D0").name)
      expect(isolated.attributes["data-unconnected"]).to eq("true")
      expect(document.to_s).to include("2 connected nets", "25 isolated")
      expect(document.root.attributes["height"].to_i).to be < 800
      block = REXML::XPath.first(document, "//g[@data-ref='UNO']/rect")
      expect(block.attributes["y"].to_i).to be < 250
    end
  end

  it "uses the selected switch state for every multi-pin terminal" do
    load_source('board :half; button :SW1, at: "e10"') do |circuit, _path, _directory|
      closed = circuit.states("all").find { |state| state.name == "SW1" }
      open_svg = REXML::Document.new(described_class.new.render(circuit))
      closed_svg = REXML::Document.new(described_class.new.render(circuit, state: closed))
      %w[1 2 3 4].each do |pin|
        terminal = "SW1.#{pin}"
        path = REXML::XPath.first(closed_svg, "//path[@data-terminal='#{terminal}']")
        expect(path.attributes["data-net"]).to eq(circuit.net_of(terminal, closed).name)
      end
      open_first = REXML::XPath.first(open_svg, "//path[@data-terminal='SW1.1']")
      open_third = REXML::XPath.first(open_svg, "//path[@data-terminal='SW1.3']")
      closed_first = REXML::XPath.first(closed_svg, "//path[@data-terminal='SW1.1']")
      closed_third = REXML::XPath.first(closed_svg, "//path[@data-terminal='SW1.3']")
      expect(open_first.attributes["data-net"]).not_to eq(open_third.attributes["data-net"])
      expect(closed_first.attributes["data-net"]).to eq(closed_third.attributes["data-net"])
      expect(closed_svg.root.attributes["data-state"]).to eq("SW1")
    end
  end

  it "bridges a net bus across an unrelated terminal wire" do
    load_source(<<~RUBY) do |circuit, _path, _directory|
      board :mini
      supply :BAT, voltage: 5, plus: "a1", minus: "a7"
      net :N0, at: "a1"
      net :N1, at: "a3"
      net :N2, at: "a5"
      net :N3, at: "a7"
      resistor :R1, "1k", pins: %w[a3 a5]
      resistor :R2, "1k", pins: %w[b1 b5]
      resistor :R3, "1k", pins: %w[b3 b7]
    RUBY
      document = REXML::Document.new(described_class.new.render(circuit))
      bridge = REXML::XPath.first(document, "//g[@id='nets']/path[@data-net='N1']")
      expect(bridge.attributes["data-crossovers"]).to eq("1")
      expect(bridge.attributes["d"]).to include(" Q ")
    end
  end
end
