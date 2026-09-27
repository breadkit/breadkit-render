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

  it "rejects parts with more than two terminals and breadboard-only controls" do
    load_source('board :mini; button :SW1, at: "e5"') do |_circuit, path, directory|
      output = File.join(directory, "schematic.svg")
      expect { expect(Breadkit::Render::CLI.new.run([path, "--view", "schematic", "-o", output])).to eq(2) }
        .to output(/schematic view supports two-terminal components; SW1 has 4 terminals/).to_stderr
    end
    load_source(source) do |_circuit, path, directory|
      output = File.join(directory, "schematic.svg")
      expect { expect(Breadkit::Render::CLI.new.run([path, "--view", "schematic", "--rail-pattern", "+--+", "-o", output])).to eq(2) }
        .to output(/--rail-pattern is unavailable in schematic view/).to_stderr
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
