# frozen_string_literal: true

require "tmpdir"

RSpec.describe "assembly guide" do
  it "exports an HTML guide with a BOM and each staged diagram" do
    Dir.mktmpdir do |dir|
      input, output = File.join(dir, "assembly.bk.rb"), File.join(dir, "guide.html")
      File.write(input, <<~RUBY)
        board :mini
        step 1, title: "Place parts" do
          resistor :R1, "330", pins: %w[a1 a3]
          resistor :R2, "330", pins: %w[a5 a7]
        end
        step 2, title: "Wire it" do
          wire "b3", "b7", color: :blue
          wire "a2", "a3", electrical: false
        end
      RUBY
      expect(Breadkit::Render::CLI.new.run([input, "--assembly-guide", "-o", output])).to eq(0)
      html = File.read(output)
      expect(html).to include('<table id="bom">', "Place parts", "Wire it", "R1, R2", "Jumper wire", "330Ω")
      expect(html).to include("1 jumper wire", "Connect b3 → b7")
      expect(html).not_to include("Connect a2 → a3", "<td>2</td><td>Jumper wire</td>")
      expect(html).not_to include('data-ref="W2"')
      expect(html.scan(/<svg\b/).length).to eq(2)
      expect(html).to include("Step 1 of 2", "Step 2 of 2")
    end
  end

  it "requires HTML output and declared assembly steps" do
    Dir.mktmpdir do |dir|
      input = File.join(dir, "empty.bk.rb")
      File.write(input, "board :mini")
      expect { expect(Breadkit::Render::CLI.new.run([input, "--assembly-guide", "-o", File.join(dir, "guide.html")])).to eq(2) }
        .to output(/no assembly steps/).to_stderr
      expect { expect(Breadkit::Render::CLI.new.run([input, "--assembly-guide", "-o", File.join(dir, "guide.svg")])).to eq(2) }
        .to output(/HTML output/).to_stderr
    end
  end
end
