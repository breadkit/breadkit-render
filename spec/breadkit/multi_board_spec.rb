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

  it "draws separate named boards and the actual cross-board jumper" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "boards.bk.rb")
      output = File.join(directory, "boards.svg")
      File.write(input, source)
      expect(Breadkit::Render::CLI.new.run([input, "-o", output])).to eq(0)
      svg = File.read(output)
      document = REXML::Document.new(svg)
      boards = REXML::XPath.match(document, "//g[@id='board']/g[@data-board]")
      expect(boards.map { |board| board.attributes["data-board"] }).to eq(%w[B1 B2])
      first, second = boards.map { |board| board.elements["rect"] }
      expect(first.attributes["x"].to_f + first.attributes["width"].to_f).to be < second.attributes["x"].to_f
      boards.each do |board|
        expect(board.elements["text"].attributes["y"].to_f).to be > board.elements["rect"].attributes["y"].to_f
      end
      expect(REXML::XPath.first(document, "//g[@id='wires']/path[@data-ref='W1']")).not_to be_nil
      expect(svg.index('id="wires"')).to be < svg.index('id="component-labels"')
      expect(REXML::XPath.first(document, "//g[@id='component-labels']/g[@data-ref='R1']/text").text).to include("R1")
      expect(REXML::XPath.first(document, "//g[@id='wires']/path[@data-ref='W1']").attributes["data-net"])
        .to eq(Breadkit.load(input).net_of("R1.1").name)
      expect(REXML::XPath.first(document, "//use[@data-hole='B1.b1']")).not_to be_nil
      expect(REXML::XPath.first(document, "//use[@data-hole='B2.b1']")).not_to be_nil
      json = File.join(directory, "boards.json")
      File.write(json, JSON.pretty_generate(Breadkit.load(input).to_ir))
      expect(Breadkit::Render::CLI.new.run([json, "-o", output])).to eq(0)
      expect(REXML::XPath.match(REXML::Document.new(File.read(output)), "//g[@id='board']/g[@data-board]").length).to eq(2)
    end
  end

  it "uses each named board's own size and rejects a shared rail pattern" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "different.bk.rb")
      output = File.join(directory, "different.svg")
      File.write(input, 'board :half, as: :B1; board :mini, as: :B2; wire "B1.a1", "B2.b1"')
      expect(Breadkit::Render::CLI.new.run([input, "--orientation", "landscape", "-o", output])).to eq(0)
      boards = REXML::XPath.match(REXML::Document.new(File.read(output)), "//g[@id='board']/g[@data-board]")
      expect(boards.first.elements["rect"].attributes["width"].to_f)
        .to be > boards.last.elements["rect"].attributes["width"].to_f
      expect { expect(Breadkit::Render::CLI.new.run([input, "--rail-pattern", "+--+", "-o", output])).to eq(2) }
        .to output(/--rail-pattern is unavailable for multi-board circuits/).to_stderr
    end
  end

  it "keeps both board plates while hiding later cross-board wiring in an early step" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "steps.bk.rb")
      early = File.join(directory, "early.svg")
      final = File.join(directory, "final.svg")
      File.write(input, <<~RUBY)
        board :mini, as: :B1
        board :mini, as: :B2
        step 1, title: "Place the first resistor" do
          resistor :R1, "330", pins: %w[B1.a1 B1.a3]
        end
        step 2, title: "Connect the second board" do
          resistor :R2, "1k", pins: %w[B2.a1 B2.a3]
          wire "B1.b1", "B2.b1"
        end
      RUBY
      expect(Breadkit::Render::CLI.new.run([input, "--step", "1", "-o", early])).to eq(0)
      expect(Breadkit::Render::CLI.new.run([input, "--step", "2", "-o", final])).to eq(0)
      first = REXML::Document.new(File.read(early))
      last = REXML::Document.new(File.read(final))
      expect(REXML::XPath.match(first, "//g[@id='board']/g[@data-board]").length).to eq(2)
      expect(REXML::XPath.match(first, "//g[@id='wires']/path")).to be_empty
      expect(REXML::XPath.match(first, "//g[@id='components']/g[@data-ref='R2']")).to be_empty
      expect(REXML::XPath.first(last, "//g[@id='wires']/path[@data-ref='W1']")).not_to be_nil
      expect(first.root.attributes["width"]).to eq(last.root.attributes["width"])
      expect(first.root.attributes["height"]).to eq(last.root.attributes["height"])
    end
  end
end
