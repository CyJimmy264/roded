require_relative "../lib/roded/frontends/curses/text_geometry"

RSpec.describe Roded::Frontends::CursesTextGeometry do
  it "maps character offsets to terminal cells across wide and combining graphemes" do
    line = "a🙂e\u0301漢x"

    expect(described_class.column(line, 0)).to eq(0)
    expect(described_class.column(line, 2)).to eq(3)
    expect(described_class.column(line, 4)).to eq(4)
    expect(described_class.column(line, 5)).to eq(6)
  end

  it "treats emoji ZWJ and skin-tone sequences as one two-cell glyph" do
    expect(described_class.width("👨‍👩‍👧‍👦👍🏽")).to eq(4)
  end

  it "clips only at grapheme boundaries within the requested cell width" do
    clipped = described_class.clip("a🙂漢x", 4)

    expect(clipped).to eq("a🙂")
    expect(described_class.width(clipped)).to be <= 4
  end

  it "keeps a wide-character caret inside the horizontal viewport" do
    expect(described_class.horizontal_origin("a🙂漢x", 4, 0, 4)).to eq(2)
  end
end
