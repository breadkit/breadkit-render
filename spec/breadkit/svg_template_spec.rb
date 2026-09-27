# frozen_string_literal: true

require "rexml/document"
require "tmpdir"
require "yaml"

RSpec.describe "part SVG templates" do
  def circuit_with_template(source)
    Dir.mktmpdir do |dir|
      definition = { "id" => "badge", "placement" => "leads", "pins" => [
        { "num" => 1, "name" => "A" }, { "num" => 2, "name" => "B" }
      ], "render" => { "shape" => "generic", "fill" => "#304050", "svg" => source } }
      File.write(File.join(dir, "badge.yml"), YAML.dump(definition))
      builder = Breadkit::DSL::Builder.new(base_dir: dir)
      builder.instance_eval('board :mini; use_parts "badge.yml"; part :X1, :badge, pins: %w[a1 a3]', "custom.bk.rb", 1)
      yield Breadkit::Resolver.new.call(builder.document)
    end
  end

  it "draws an allowed custom body centered on its pins and substitutes escaped labels" do
    template = '<circle cx="0" cy="0" r="5" fill="{{fill}}"/><text x="0" y="1">{{ref}}</text>'
    circuit_with_template(template) do |circuit|
      document = REXML::Document.new(Breadkit::Render::SvgRenderer.new.render(circuit))
      group = REXML::XPath.first(document, "//g[@id='components']/g[@data-ref='X1']")
      expect(group.elements["g[@data-part-template='badge']/circle"].attributes["fill"]).to eq("#304050")
      expect(group.elements["g[@data-part-template='badge']/text"].text).to eq("X1")
      expect(group.elements.to_a("line")).not_to be_empty
    end
  end

  it "rejects active SVG elements, event handlers, URL paints, and unknown variables" do
    ['<script>alert(1)</script>', '<circle r="5" onclick="alert(1)"/>',
     '<circle r="5" fill="url(https://example.com/x)"/>', '<text>{{secret}}</text>',
     '<foreignObject><html/></foreignObject>', '<image href="https://example.com/x"/>',
     '<!DOCTYPE svg [<!ENTITY x SYSTEM "file:///etc/passwd">]><text>&x;</text>'].each do |template|
      circuit_with_template(template) do |circuit|
        expect { Breadkit::Render::SvgRenderer.new.render(circuit) }.to raise_error(Breadkit::Render::Error, /template/)
      end
    end
  end

  it "escapes substituted text and bounds expanded markup" do
    renderer = Breadkit::Render::SvgTemplate.new("<text>{{ref}}</text>")
    values = { "ref" => 'X<&"' }
    expect(renderer.render(values)).to eq('<text>X&lt;&amp;&quot;</text>')
    expect { renderer.render("ref" => "x" * (32 * 1024)) }.to raise_error(Breadkit::Render::Error, /exceeds/)
  end
end
