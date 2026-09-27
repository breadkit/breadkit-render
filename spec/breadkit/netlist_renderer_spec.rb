# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "rexml/xpath"
require "tmpdir"

RSpec.describe Breadkit::Render::NetlistRenderer do
  let(:input) { File.expand_path("../../../breadkit/examples/01_led_button.bk.rb", __dir__) }
  let(:circuit) { Breadkit.load(input) }

  it "draws every component and supply terminal on its resolved net" do
    document = REXML::Document.new(described_class.new.render(circuit))
    expect(document.root.attributes["data-view"]).to eq("netlist")
    expect(document.root.elements["title"].text).to eq("Circuit netlist")
    vcc = circuit.nets.find { |net| net.name == "VCC" }
    expect(document.root.elements["desc"].text).to include("VCC: #{vcc.members.join(', ')}")

    terminals = circuit.components.values.flat_map { |component| component.pins.values.map { |pin| "#{component.ref}.#{pin.name}" } }
    terminals.concat(circuit.supplies.flat_map { |supply| ["#{supply.name}.+", "#{supply.name}.-"] })
    connections = REXML::XPath.match(document, "//path[@data-terminal]")
    expect(connections.map { |path| path.attributes["data-terminal"] }).to match_array(terminals)
    connections.each do |path|
      terminal = path.attributes["data-terminal"]
      expect(path.attributes["data-net"]).to eq(circuit.net_of(terminal).name)
    end

    expect(REXML::XPath.match(document, "//g[@id='nets']/g").map { |net| net.attributes["data-net"] }).to match_array(circuit.nets.map(&:name))
    expect(document.to_s).to include("VCC", "GND", "USB", "5 V")
  end

  it "keeps a larger circuit legible by grouping terminal connections inside each net" do
    large = Breadkit.load(File.expand_path("../../../breadkit/examples/05_sensor_demo.bk.rb", __dir__))
    document = REXML::Document.new(described_class.new.render(large, theme: "dark"))
    net_groups = REXML::XPath.match(document, "//g[@id='nets']/g[@data-net]")
    expect(net_groups.length).to eq(large.nets.length)
    expect(net_groups.length).to be > 16
    terminal_ids = large.components.values.flat_map { |component| component.pins.values.map { |pin| "#{component.ref}.#{pin.name}" } }
    terminal_ids.concat(large.supplies.flat_map { |supply| ["#{supply.name}.+", "#{supply.name}.-"] })
    net_groups.each do |group|
      paths = REXML::XPath.match(group, ".//path[@data-terminal]")
      net = large.nets.find { |candidate| candidate.name == group.attributes["data-net"] }
      expect(paths.map { |path| path.attributes["data-terminal"] }).to match_array(net.members & terminal_ids)
      paths.each do |path|
        expect(path.attributes["data-net"]).to eq(group.attributes["data-net"])
        expect(path.attributes["d"]).not_to include(" H ")
      end
    end
    expect(REXML::XPath.match(document, "//path[@data-terminal]").length)
      .to eq(terminal_ids.length)
  end

  it "uses the selected switch state when assigning terminals to nets" do
    state = circuit.states("all").find { |candidate| candidate.name == "SW1" }
    document = REXML::Document.new(described_class.new.render(circuit, state: state, theme: "dark"))
    connection = REXML::XPath.first(document, "//path[@data-terminal='SW1.3']")
    expect(connection.attributes["data-net"]).to eq(circuit.net_of("SW1.3", state).name)
    expect(document.root.attributes["data-state"]).to eq("SW1")
    expect(document.root.attributes["data-theme"]).to eq("dark")
  end

  it "selects the netlist view through the CLI and rejects incompatible controls" do
    Dir.mktmpdir do |directory|
      output = File.join(directory, "netlist.svg")
      expect(Breadkit::Render::CLI.new.run([input, "--view", "netlist", "-o", output])).to eq(0)
      expect(REXML::Document.new(File.read(output)).root.attributes["data-view"]).to eq("netlist")
      expect(Breadkit::Render::CLI.new.run([input, "-o", output])).to eq(0)
      expect(REXML::Document.new(File.read(output)).root.attributes["data-view"]).not_to eq("netlist")
      expect { expect(Breadkit::Render::CLI.new.run([input, "--view", "netlist", "--layer", "Power", "-o", output])).to eq(2) }
        .to output(/--layer is unavailable in netlist view/).to_stderr
      expect { expect(Breadkit::Render::CLI.new.run([input, "--view", "netlist", "-o", File.join(directory, "netlist.html")])).to eq(2) }
        .to output(/HTML is unavailable in netlist view/).to_stderr
    end
  end
end
