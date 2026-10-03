require_relative "../lib/roded/frontends/curses/text_geometry"

RSpec.describe Roded::Frontends::CursesTextGeometry, "tab stops" do
  it "expands tabs at two-cell stops for columns, widths, and clipping" do
    expect(described_class.column("a\tb", 2)).to eq(2)
    expect(described_class.width("ab\tc")).to eq(5)
    expect(described_class.clip("a\tb", 3)).to eq("a b")
    expect(described_class.clip("\tb", 2, initial_column: 1)).to eq(" b")
  end

  it "accounts for tab stops when choosing a horizontal origin" do
    expect(described_class.horizontal_origin("ab\tcdef", 6, 0, 3)).to eq(4)
  end
end
