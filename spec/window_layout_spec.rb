RSpec.describe Roded::WindowLayout, "split rectangles" do
  it "calculates nested horizontal and vertical split rectangles" do
    buffer = Roded::Buffer.new("doc")
    first = Roded::Window.new(buffer)
    second = first.copy
    third = first.copy
    layout = described_class.new(first)
    layout.split(first, second, :vertical)
    layout.split(second, third, :horizontal)

    expect(layout.rectangles(80, 24).map(&:last)).to eq([
                                                          described_class::Rectangle.new(x: 0, y: 0, width: 40,
                                                                                         height: 24),
                                                          described_class::Rectangle.new(x: 40, y: 0, width: 40,
                                                                                         height: 12),
                                                          described_class::Rectangle.new(x: 40, y: 12, width: 40,
                                                                                         height: 12)
                                                        ])
  end
end

RSpec.describe Roded::WindowLayout, "split removal" do
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

RSpec.describe Roded::WindowLayout, "split resizing" do
  it "resizes the active side of a vertical split within safe bounds" do
    buffer = Roded::Buffer.new("doc")
    first = Roded::Window.new(buffer)
    second = first.copy
    layout = described_class.new(first)
    layout.split(first, second, :vertical)

    expect(layout.resize_columns(second, -0.1)).to be(true)
    expect(layout.rectangles(80, 24).map(&:last).map(&:width)).to eq([48, 32])
    expect(layout.resize_columns(first, -0.8)).to be(true)
    expect(layout.rectangles(80, 24).map(&:last).map(&:width)).to eq([8, 72])
  end
end
