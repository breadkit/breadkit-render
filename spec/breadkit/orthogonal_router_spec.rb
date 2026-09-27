# frozen_string_literal: true

require "rexml/document"

RSpec.describe Breadkit::Render::OrthogonalRouter do
  it "keeps a right-angle jumper clear of a component body" do
    router = described_class.new([[4, 4, 6, 6]])
    points = router.route([1, 5], [9, 5])
    expect(points.first).to eq([1, 5])
    expect(points.last).to eq([9, 5])
    expect(points.each_cons(2).all? { |from, to| from[0] == to[0] || from[1] == to[1] }).to be(true)
    expect(points.each_cons(2).any? do |from, to|
      from[0] == to[0] ? from[0].between?(4, 6) && [from[1], to[1]].min < 6 && [from[1], to[1]].max > 4 :
        from[1].between?(4, 6) && [from[0], to[0]].min < 6 && [from[0], to[0]].max > 4
    end).to be(false)
  end

  it "chooses another track for a second wire with the same endpoints" do
    router = described_class.new([[4, 4, 6, 6]])
    first = router.route([1, 5], [9, 5])
    second = router.route([1, 5], [9, 5])
    expect(second).not_to eq(first)
  end
end

RSpec.describe "automatic jumper rendering" do
  it "keeps endpoints and draws a flat orthogonal route around a switch" do
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval('board :mini; button :SW1, at: "e5"; wire "a5", "j5"', "jumper.bk.rb", 1)
    circuit = Breadkit::Resolver.new.call(builder.document)
    svg = Breadkit::Render::SvgRenderer.new.render(circuit, wire_routing: "auto", wire_style: "flat")
    document = REXML::Document.new(svg)
    path = REXML::XPath.first(document, "//g[@id='wires']//path[@data-ref='W1']")
    from, to = %w[a5 j5].map { |id| circuit.board.hole(id) }
    expect(path.attributes["d"]).to start_with("M #{format('%.2f', from.x * 10)} #{format('%.2f', (circuit.board.height - 1 - from.y) * 10)}")
    expect(path.attributes["d"]).to end_with("#{format('%.2f', to.x * 10)} #{format('%.2f', (circuit.board.height - 1 - to.y) * 10)}")
    expect(path.attributes["d"].scan(" L ").length).to be > 1
    expect(REXML::XPath.match(document, "//g[@id='wires']//path").length).to eq(1)
  end
end
