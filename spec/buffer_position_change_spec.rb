module BufferPositionChangeReference
  def reference_change(row, before_lines, after_lines)
    before = before_lines.join("\n").each_char.to_a
    after = after_lines.join("\n").each_char.to_a
    first = shared_prefix(before, after)
    return if first == before.length && first == after.length

    last = shared_suffix(before, after, first)
    reference_span(row, before, after, first, last)
  end

  def reference_span(row, before, after, first, last)
    Roded::Buffer::PositionChange.new(
      start: reference_position(row, before.take(first)),
      old_end: reference_position(row, before.take(before.length - last)),
      new_end: reference_position(row, after.take(after.length - last))
    )
  end

  def shared_prefix(before, after)
    first = 0
    first += 1 while first < [before.length, after.length].min && before[first] == after[first]
    first
  end

  def shared_suffix(before, after, first)
    last = 0
    last += 1 while last < [before.length, after.length].min - first && before[-last - 1] == after[-last - 1]
    last
  end

  def reference_position(row, characters)
    lines = characters.join.split("\n", -1)
    lines = [""] if lines.empty?
    { row: row + lines.length - 1, col: lines.last.length }
  end

  def random_lines(random)
    alphabet = ["a", "b", "é", "ê", "ĩ", "🙂", "🙃", "界", "\t", "\u0301"]
    Array.new(random.rand(1..6)) { Array.new(random.rand(0..12)) { alphabet.sample(random:) }.join }
  end
end

RSpec.describe Roded::Buffer, "position change ranges" do
  include BufferPositionChangeReference

  it "matches character-based ranges for Unicode substitutions and line insertions or deletions" do
    random = Random.new(264)
    buffer = described_class.new
    600.times do
      before = random_lines(random)
      after = random_lines(random)
      after = before.dup.insert(random.rand(0..before.length), "") if random.rand(2).zero?
      expect(buffer.send(:position_change, 7, before, after)).to eq(reference_change(7, before, after))
    end
  end

  it "preserves ranges when changed UTF-8 characters share leading or trailing bytes" do
    buffer = described_class.new
    [["é", "ê"], ["é", "ĩ"], ["🙂", "🙃"]].each do |before, after|
      expect(buffer.send(:position_change, 3, [before], [after])).to eq(
        Roded::Buffer::PositionChange.new(start: { row: 3, col: 0 }, old_end: { row: 3, col: 1 },
                                          new_end: { row: 3, col: 1 })
      )
    end
  end
end

RSpec.describe Roded::Buffer, "long document position ranges" do
  it "finds the changed range inside a long Unicode document" do
    before = Array.new(1500, "prefix🙂suffix")
    before[750] = "before🙂é"
    after = before.dup
    after[750, 1] = ["before🙂ê", "x"]
    change = Roded::Buffer::PositionChange.new(start: { row: 750, col: 7 }, old_end: { row: 750, col: 8 },
                                               new_end: { row: 751, col: 1 })
    expect(described_class.new.send(:position_change, 0, before, after)).to eq(change)
  end
end

RSpec.describe Roded::Buffer, "position range history" do
  it "publishes precise replacement and inverse ranges after skipping equal prefix and suffix lines" do
    buffer = described_class.new.load_text("prefix\né\nsuffix\n")
    observer = double("Edit observer", buffer_edited: nil)
    buffer.add_edit_observer(observer)
    change = Roded::Buffer::PositionChange.new(start: { row: 1, col: 0 }, old_end: { row: 1, col: 1 },
                                               new_end: { row: 2, col: 1 })
    buffer.lines = ["prefix", "ĩ", "🙂", "suffix", ""]
    expect(observer).to have_received(:buffer_edited).with(buffer, change)
    buffer.undo
    inverse = Roded::Buffer::PositionChange.new(start: change.start, old_end: change.new_end, new_end: change.old_end)
    expect(observer).to have_received(:buffer_edited).with(buffer, inverse)
    expect(buffer.to_s).to eq("prefix\né\nsuffix\n")
    buffer.redo
    expect(observer).to have_received(:buffer_edited).with(buffer, change).twice
  end

  it "retains character semantics for binary and invalid strings assigned through the legacy lines API" do
    buffer = described_class.new
    before = "\x80".b
    after = "\x81".b
    change = Roded::Buffer::PositionChange.new(start: { row: 0, col: 0 }, old_end: { row: 0, col: 1 },
                                               new_end: { row: 0, col: 1 })
    expect(buffer.send(:position_change, 0, [before], [after])).to eq(change)
    expect(buffer.send(:position_change, 0, [before.dup.force_encoding("UTF-8")],
                       [after.dup.force_encoding("UTF-8")])).to eq(change)
  end
end
