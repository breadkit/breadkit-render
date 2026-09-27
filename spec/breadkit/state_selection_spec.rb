# frozen_string_literal: true

require "tmpdir"

RSpec.describe "switch state selection" do
  def many_switches(path)
    source = ["board :full"] + 9.times.map { |index| "button :SW#{index + 1}, at: 'e#{1 + index * 4}'" }
    File.write(path, source.join("\n"))
  end

  it "renders a requested combined state without enumerating every combination" do
    Dir.mktmpdir do |dir|
      input, output = File.join(dir, "switches.bk.rb"), File.join(dir, "chosen.svg")
      many_switches(input)
      expect(Breadkit::Render::CLI.new.run([input, "--state", "SW1,SW9", "-o", output])).to eq(0)
      expect(File.read(output)).to include('data-state="SW1,SW9"')
    end
  end

  it "fails clearly when an HTML viewer would need more than 256 states" do
    Dir.mktmpdir do |dir|
      input = File.join(dir, "switches.bk.rb")
      many_switches(input)
      expect { expect(Breadkit::Render::CLI.new.run([input, "-o", File.join(dir, "switches.html")])).to eq(2) }
        .to output(/512 switch states exceed budget 256/).to_stderr
    end
  end
end
