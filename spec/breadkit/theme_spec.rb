# frozen_string_literal: true

require "rexml/document"
require "tmpdir"

RSpec.describe "custom breadboard appearance" do
  let(:input) { File.expand_path("../../../breadkit/examples/01_led_button.bk.rb", __dir__) }

  it "overrides palette colors from a checked theme file" do
    Dir.mktmpdir do |dir|
      theme = File.join(dir, "theme.json")
      output = File.join(dir, "board.svg")
      File.write(theme, JSON.generate("base" => "dark", "colors" => { "board" => "#112233", "text" => "#fefefe" }))

      expect(Breadkit::Render::CLI.new.run([input, "--theme-file", theme, "-o", output])).to eq(0)
      svg = File.read(output)
      expect(svg).to include('fill="#112233"', 'fill="#fefefe"')
    end
  end

  it "rejects unknown color keys and invalid colors" do
    Dir.mktmpdir do |dir|
      theme = File.join(dir, "theme.json")
      File.write(theme, JSON.generate("base" => "dark", "colors" => { "mystery" => "#112233" }))
      expect { Breadkit::Render::Theme.load(theme) }.to raise_error(Breadkit::Render::Error, /unknown theme color/)
      File.write(theme, JSON.generate("base" => "dark", "colors" => { "board" => 'red" onload="evil' }))
      expect { Breadkit::Render::Theme.load(theme) }.to raise_error(Breadkit::Render::Error, /invalid theme color/)
    end
  end

  it "embeds a font in standalone SVG without exposing font data as markup" do
    Dir.mktmpdir do |dir|
      font = File.join(dir, "test.woff2")
      output = File.join(dir, "board.svg")
      File.binwrite(font, "wOF2<script>".b)

      expect(Breadkit::Render::CLI.new.run([input, "--font-file", font, "-o", output])).to eq(0)
      document = REXML::Document.new(File.read(output))
      style = document.root.elements["style"]
      expect(style.text).to include("data:font/woff2;base64,", "font-family:BreadkitEmbedded")
      expect(document.root.attributes["font-family"]).to include("BreadkitEmbedded")
      expect(document.to_s).not_to include("<script>")
    end
  end

  it "rejects unsupported and oversized font files" do
    Dir.mktmpdir do |dir|
      bad = File.join(dir, "font.svg")
      File.write(bad, "<svg/>")
      expect { Breadkit::Render::Theme.font(bad) }.to raise_error(Breadkit::Render::Error, /unsupported font format/)
      big = File.join(dir, "font.ttf")
      File.binwrite(big, "a" * (5 * 1024 * 1024 + 1))
      expect { Breadkit::Render::Theme.font(big) }.to raise_error(Breadkit::Render::Error, /too large/)
    end
  end
end
