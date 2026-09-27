# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "rexml/xpath"
require "tmpdir"

RSpec.describe "assembly step rendering" do
  let(:source) do
    <<~RUBY
      board :half
      step 1, title: "Install the supply and resistor" do
        supply :USB, voltage: 5, plus: "B+1", minus: "B-1"
        resistor :R1, "330", pins: %w[a12 a16]
      end
      step 2, title: "Add the LED and return wire" do
        led :D1, anode: "b16", cathode: "b17", color: :red
        wire "b12", "B+2", color: :red
        wire "a17", "B-2", color: :black
      end
    RUBY
  end

  it "renders staged declarations with recomputed nets and fixed board geometry" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "steps.bk.rb")
      early_path = File.join(directory, "early.svg")
      final_path = File.join(directory, "final.svg")
      File.write(input, source)
      cli = Breadkit::Render::CLI.new
      expect(cli.run([input, "--step", "1", "-o", early_path])).to eq(0)
      expect(cli.run([input, "--step", "2", "-o", final_path])).to eq(0)
      early, final = [early_path, final_path].map { |path| REXML::Document.new(File.read(path)) }

      expect(early.root.attributes["data-step"]).to eq("1")
      early_title = REXML::XPath.match(early, "//g[@id='assembly-step-title']/text").map(&:text)
      final_title = REXML::XPath.match(final, "//g[@id='assembly-step-title']/text").map(&:text)
      expect(early_title.join(" ")).to eq("Step 1 of 2 Install the supply and resistor")
      expect(final_title.join(" ")).to eq("Step 2 of 2 Add the LED and return wire")
      expect(early_title.length).to be > 2
      expect(early.root.attributes["height"]).to eq(final.root.attributes["height"])
      expect(REXML::XPath.first(early, "//g[@id='components']//*[@data-ref='D1']")).to be_nil
      expect(REXML::XPath.first(final, "//g[@id='components']//*[@data-ref='D1']")).not_to be_nil
      expect(REXML::XPath.first(early, "//g[@id='wires']//*[@data-ref='W1']")).to be_nil
      expect(REXML::XPath.first(final, "//g[@id='wires']//*[@data-ref='W1']")).not_to be_nil
      expect(REXML::XPath.first(early, "//desc").text).not_to include("D1.anode", "W1")
      expect(REXML::XPath.first(final, "//desc").text).to include("D1.anode", "W1")
      expect(REXML::XPath.first(early, "//svg[@id='step-board']").attributes["viewBox"])
        .to eq(REXML::XPath.first(final, "//svg[@id='step-board']").attributes["viewBox"])
    end
  end

  it "reads the same step metadata from JSON IR" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "steps.bk.rb")
      json = File.join(directory, "steps.json")
      output = File.join(directory, "early.svg")
      File.write(input, source)
      File.write(json, JSON.pretty_generate(Breadkit.load(input).to_ir))
      expect(Breadkit::Render::CLI.new.run([json, "--step", "1", "-o", output])).to eq(0)
      expect(REXML::Document.new(File.read(output)).root.attributes["data-step"]).to eq("1")
    end
  end

  it "rejects missing steps and unsupported view combinations" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "steps.bk.rb")
      plain = File.join(directory, "plain.bk.rb")
      File.write(input, source)
      File.write(plain, 'board :half; resistor :R1, "330", pins: %w[a1 a3]')
      cli = Breadkit::Render::CLI.new
      expect { expect(cli.run([input, "--step", "3"])).to eq(2) }.to output(/unknown assembly step: 3/).to_stderr
      expect { expect(cli.run([input, "--step", "0"])).to eq(2) }.to output(/--step must be a positive integer/).to_stderr
      expect { expect(cli.run([plain, "--step", "1"])).to eq(2) }.to output(/no assembly steps/).to_stderr
      expect { expect(cli.run([input, "--step", "1", "--view", "netlist"])).to eq(2) }
        .to output(/--step is unavailable in netlist view/).to_stderr
      expect { expect(cli.run([input, "--step", "1", "-f", "html"])).to eq(2) }
        .to output(/--step requires SVG or image output/).to_stderr
    end
  end

  it "shows a wire placed before a component without including the future pin in its net" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "forward.bk.rb")
      File.write(input, <<~RUBY)
        board :half
        step 1 do
          wire "R1.1", "b2"
        end
        step 2 do
          resistor :R1, "330", pins: %w[a1 a3]
        end
      RUBY
      output = File.join(directory, "early.svg")
      expect(Breadkit::Render::CLI.new.run([input, "--step", "1", "-o", output])).to eq(0)
      document = REXML::Document.new(File.read(output))
      expect(REXML::XPath.first(document, "//g[@id='wires']//*[@data-ref='W1']")).not_to be_nil
      expect(REXML::XPath.first(document, "//g[@id='components']//*[@data-ref='R1']")).to be_nil
      expect(REXML::XPath.first(document, "//desc").text).not_to include("R1.1")
    end
  end

  it "keeps the default view compatible with circuits without step metadata" do
    circuit = Breadkit.load(File.expand_path("../../../breadkit/examples/01_led_button.bk.rb", __dir__))
    circuit.singleton_class.class_eval do
      undef_method :steps
      undef_method :multi_board?
    end
    allow(Breadkit).to receive(:load).and_return(circuit)
    Dir.mktmpdir do |directory|
      output = File.join(directory, "circuit.svg")
      expect(Breadkit::Render::CLI.new.run(["legacy.bk.rb", "-o", output])).to eq(0)
      expect(File.read(output)).to include("<svg")
    end
  end
end
