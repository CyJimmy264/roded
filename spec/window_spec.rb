RSpec.describe Roded::Window do
  it "keeps point and mark state independently between views" do
    buffer = Roded::Buffer.new("first")
    buffer.lines = ["first"]
    window = described_class.new(buffer)
    other = described_class.new(buffer)

    window.point = { row: 0, col: 2 }
    window.mark = { row: 0, col: 1 }

    expect(other.point).to eq({ row: 0, col: 0 })
    expect(other.mark).to be_nil
    expect(window.point).to eq({ row: 0, col: 2 })
    expect(window.mark).to eq({ row: 0, col: 1 })
  end
end

RSpec.describe Roded::Window do
  it "remembers point and mark for each buffer when switching" do
    buffer = Roded::Buffer.new("first")
    buffer.lines = ["first"]
    other = Roded::Buffer.new("second")
    other.lines = ["second"]
    window = described_class.new(buffer)

    window.point = { row: 0, col: 3 }
    window.mark = { row: 0, col: 1 }
    window.buffer = other
    window.point = { row: 0, col: 2 }
    window.buffer = buffer

    expect(window.point).to eq({ row: 0, col: 3 })
    expect(window.mark).to eq({ row: 0, col: 1 })
    window.buffer = other
    expect(window.point).to eq({ row: 0, col: 2 })
  end
end

RSpec.describe Roded::Window do
  it "clamps point and mark to the active buffer" do
    buffer = Roded::Buffer.new("first")
    buffer.lines = %w[one two]
    window = described_class.new(buffer)
    window.point = { row: 20, col: 20 }
    window.mark = { row: -1, col: -1 }

    expect(window.point).to eq({ row: 1, col: 3 })
    expect(window.mark).to eq({ row: 0, col: 0 })
  end
end
