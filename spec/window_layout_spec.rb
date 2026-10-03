RSpec.describe Roded::WindowLayout do
  it "calculates nested horizontal and vertical split rectangles" do
    buffer = Roded::Buffer.new("doc")
    first = Roded::Window.new(buffer)
    second = first.copy
    third = first.copy
    layout = described_class.new(first)
    layout.split(first, second, :vertical)
    layout.split(second, third, :horizontal)

    expect(layout.rectangles(80, 24).map(&:last)).to eq([
      described_class::Rectangle.new(x: 0, y: 0, width: 40, height: 24),
      described_class::Rectangle.new(x: 40, y: 0, width: 40, height: 12),
      described_class::Rectangle.new(x: 40, y: 12, width: 40, height: 12)
    ])
  end

  it "collapses a split after removing a leaf and can keep one window" do
    buffer = Roded::Buffer.new("doc")
    first = Roded::Window.new(buffer)
    second = first.copy
    third = first.copy
    layout = described_class.new(first)
    layout.split(first, second, :vertical)
    layout.split(second, third, :horizontal)

    expect(layout.remove(second)).to be(true)
    expect(layout.windows).to eq([first, third])
    layout.keep(third)
    expect(layout.windows).to eq([third])
  end
end
