RSpec.describe Roded::Buffer, "repeated character insertion" do
  it "advances both views and groups consecutive repeated ASCII and Unicode input" do
    ["a", "🙂"].each do |char|
      buffer = described_class.new.load_text(char * 4)
      window = Roded::Window.new(buffer)
      other = Roded::Window.new(buffer)
      window.point = other.point = { row: 0, col: 1 }
      other.mark = { row: 0, col: 0 }
      50.times do |index|
        buffer.insert_char(char, at: window.point)
        expect(window.point).to eq({ row: 0, col: index + 2 })
        expect(other.point).to eq(window.point)
      end
      expect(other.mark).to eq({ row: 0, col: 0 })
      buffer.undo
      expect(buffer.to_s).to eq(char * 4)
      expect(window.point).to eq({ row: 0, col: 1 })
      expect(buffer.undo).to be(false)
      buffer.redo
      expect(window.point).to eq({ row: 0, col: 51 })
    end
  end
end

RSpec.describe Roded::Buffer, "repeated character deletion" do
  it "transforms point and mark at the actual deletion rather than the final repeated character" do
    [[:backspace, 2], [:delete_char, 1]].each do |operation, column|
      buffer = described_class.new.load_text("🙂🙂🙂🙂")
      window = Roded::Window.new(buffer)
      window.point = { row: 0, col: 2 }
      window.mark = { row: 0, col: 3 }
      buffer.public_send(operation, at: { row: 0, col: column })
      expect(window.point).to eq({ row: 0, col: 1 })
      expect(window.mark).to eq({ row: 0, col: 2 })
      buffer.undo
      expect(window.point).to eq({ row: 0, col: 2 })
      expect(window.mark).to eq({ row: 0, col: 3 })
    end
  end
end

RSpec.describe Roded::Buffer, "repeated text paste" do
  it "moves the caret to the actual paste end for single and multiple lines" do
    ["aaa", "a\r\na"].each do |text|
      buffer = described_class.new.load_text("aaaa")
      window = Roded::Window.new(buffer)
      window.point = { row: 0, col: 1 }
      buffer.insert_text(text, at: window.point)
      expected = text.include?("\n") ? { row: 1, col: 1 } : { row: 0, col: 4 }
      expect(window.point).to eq(expected)
      buffer.undo
      expect(window.point).to eq({ row: 0, col: 1 })
      expect(buffer.to_s).to eq("aaaa")
      buffer.redo
      expect(window.point).to eq(expected)
    end
  end
end

RSpec.describe Roded::Buffer, "repeated text region deletion" do
  it "moves positions following a reversed region in repeated text" do
    buffer = described_class.new.load_text("aaaaaa")
    window = Roded::Window.new(buffer)
    window.point = { row: 0, col: 4 }
    window.mark = { row: 0, col: 5 }
    buffer.delete_region({ row: 0, col: 3 }, { row: 0, col: 1 })
    expect(window.point).to eq({ row: 0, col: 2 })
    expect(window.mark).to eq({ row: 0, col: 3 })
    buffer.undo
    expect(window.point).to eq({ row: 0, col: 4 })
    expect(window.mark).to eq({ row: 0, col: 5 })
  end
end

RSpec.describe Roded::Buffer, "blank line splitting" do
  it "advances at the actual split among identical empty lines" do
    buffer = described_class.new.load_text("\n\n\n")
    window = Roded::Window.new(buffer)
    window.point = { row: 1, col: 0 }
    window.mark = { row: 2, col: 0 }
    buffer.newline(at: window.point)
    expect(window.point).to eq({ row: 2, col: 0 })
    expect(window.mark).to eq({ row: 3, col: 0 })
    buffer.undo
    expect(window.point).to eq({ row: 1, col: 0 })
    expect(window.mark).to eq({ row: 2, col: 0 })
  end
end

RSpec.describe Roded::Buffer, "blank line joining" do
  it "transforms rows after the actual newline removed by backspace, delete or kill" do
    [[:backspace, 2], [:delete_char, 1], [:kill_line, 1]].each do |operation, row|
      buffer = described_class.new.load_text("\n\n\n\n")
      window = Roded::Window.new(buffer)
      window.point = { row: 2, col: 0 }
      window.mark = { row: 3, col: 0 }
      buffer.public_send(operation, at: { row:, col: 0 })
      expect(window.point).to eq({ row: 1, col: 0 })
      expect(window.mark).to eq({ row: 2, col: 0 })
      buffer.undo
      expect(window.point).to eq({ row: 2, col: 0 })
      expect(window.mark).to eq({ row: 3, col: 0 })
    end
  end
end
