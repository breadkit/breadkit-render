# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "rexml/xpath"
require "tmpdir"

RSpec.describe "named board rendering" do
  let(:source) do
    <<~RUBY
      board :mini, as: :B1
      board :mini, as: :B2
      resistor :R1, "330", pins: %w[B1.a1 B1.a3]
      resistor :R2, "1k", pins: %w[B2.a1 B2.a3]
      wire "B1.b1", "B2.b1"
    RUBY
  end

  it "renders v2 circuit terminal memberships in the netlist view" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "boards.bk.rb")
      output = File.join(directory, "boards.svg")
      File.write(input, source)
      circuit = Breadkit.load(input)
      expect(circuit.multi_board?).to be(true)
      expect(Breadkit::Render::CLI.new.run([input, "--view", "netlist", "-o", output])).to eq(0)
      document = REXML::Document.new(File.read(output))
      %w[R1.1 R1.2 R2.1 R2.2].each do |terminal|
        path = REXML::XPath.first(document, "//path[@data-terminal='#{terminal}']")
        expect(path.attributes["data-net"]).to eq(circuit.net_of(terminal).name)
      end
      expect(circuit.net_of("R1.1")).to eq(circuit.net_of("R2.1"))
      json = File.join(directory, "boards.json")
      File.write(json, JSON.pretty_generate(circuit.to_ir))
      expect(Breadkit::Render::CLI.new.run([json, "--view", "netlist", "-o", output])).to eq(0)
      expect(REXML::Document.new(File.read(output)).root.attributes["data-view"]).to eq("netlist")
    end
  end

  it "rejects unsupported multi-board breadboard output clearly" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "boards.bk.rb")
      File.write(input, source)
      expect { expect(Breadkit::Render::CLI.new.run([input])).to eq(2) }
        .to output(/multi-board breadboard rendering is not yet supported/).to_stderr
    end
  end
end
