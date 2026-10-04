require "spec_helper"

# rubocop:disable Metrics/BlockLength

RSpec.describe Roded::Buffer, "cached immutable document snapshots" do
  it "reuses snapshots until an edit and keeps old snapshots stable through undo and reload" do
    buffer = described_class.new.load_text("alpha\nbeta")
    lines = buffer.lines
    text = buffer.text_snapshot
    revision = buffer.revision
    expect(buffer.lines).to equal(lines)
    expect(buffer.text_snapshot).to equal(text)
    buffer.insert_text("X", at: { row: 1, col: 2 })
    expect(buffer.lines).to eq(%w[alpha beXta])
    expect(buffer.lines.first).to equal(lines.first)
    expect(buffer.text_snapshot).to eq("alpha\nbeXta")
    expect(lines).to eq(%w[alpha beta])
    expect(text).to eq("alpha\nbeta")
    expect(buffer.revision).to be > revision
    buffer.undo
    expect(buffer.text_snapshot).to eq(text)
    expect(buffer.modified?).to be(false)
    buffer.redo
    expect(buffer.modified?).to be(true)
    buffer.load_text("replacement\r\n")
    expect(buffer.text_snapshot).to eq("replacement\r\n")
    expect(buffer.modified?).to be(false)
  end

  it "copies caller-owned strings and keeps to_s independently mutable" do
    line = +"caller"
    buffer = described_class.new
    buffer.lines = [line]
    snapshot = buffer.lines
    line << " changed"
    serialized = buffer.to_s
    serialized << " changed"
    expect(snapshot).to eq(["caller"])
    expect(buffer.text_snapshot).to eq("caller")
    expect(buffer.text_snapshot).to be_frozen
    expect(buffer.to_s).not_to be_frozen
  end

  it "invalidates snapshots for newline metadata and history replay" do
    buffer = described_class.new.load_text("alpha\nbeta")
    buffer.lines
    buffer.text_snapshot
    buffer.line_ending = "\r\n"
    expect(buffer.text_snapshot).to eq("alpha\r\nbeta")
    buffer.final_newline = true
    expect(buffer.lines).to eq(["alpha", "beta", ""])
    expect(buffer.text_snapshot).to eq("alpha\r\nbeta\r\n")
    buffer.undo
    expect(buffer.text_snapshot).to eq("alpha\r\nbeta")
    buffer.undo
    expect(buffer.text_snapshot).to eq("alpha\nbeta")
  end
end

RSpec.describe Roded::Application, "document snapshot reuse" do
  it "publishes one final frame per command including multi-window edits" do
    app = described_class.new
    app.startup
    frontend = FakeFrontend.new
    app.add_frontend(frontend)
    app.handle_event(Roded::Event.new(:split_vertical, {}))
    frontend.commands.clear
    app.handle_event(Roded::Event.new(:insert_char, { char: "x" }))
    renders = frontend.commands.select { |command| command.type == :render }
    expect(renders.length).to eq(1)
    expect(renders.first.payload[:editor_snapshot][:windows].map { |item| item[:text] }).to eq(%w[x x])
  end

  it "shares document content across cursor changes and windows while updating positions and edits" do
    app = described_class.new
    app.startup
    app.current_buffer.load_text("first\nsecond")
    before = app.editor_snapshot[:windows].first
    app.handle_event(Roded::Event.new(:move_down, {}))
    moved = app.editor_snapshot[:windows].first
    expect(moved[:text]).to equal(before[:text])
    expect(moved[:lines]).to equal(before[:lines])
    expect(moved[:tokens]).to equal(before[:tokens])
    expect(moved[:point]).to eq(row: 1, col: 0)
    app.split_window(:vertical)
    snapshot = app.editor_snapshot
    expect(snapshot[:windows].first[:lines]).to equal(snapshot[:windows].last[:lines])
    app.handle_event(Roded::Event.new(:insert_char, { char: "x" }))
    edited = app.editor_snapshot[:windows].last
    expect(edited[:text]).to eq("first\nxsecond")
    expect(edited[:modified]).to be(true)
    expect(before[:text]).to eq("first\nsecond")
  end

  it "releases edit observers for deleted windows and every buffer they visited" do
    app = described_class.new
    app.startup
    first = app.current_buffer
    second = Roded::Buffer.new("other")
    app.add_buffer(second)
    split = app.split_window(:vertical)
    split.buffer = second
    app.delete_window
    expect(first.instance_variable_get(:@edit_observers)).not_to include(split)
    expect(second.instance_variable_get(:@edit_observers)).not_to include(split)
    app.split_window(:vertical)
    other = app.split_window(:horizontal)
    app.delete_other_windows
    expect(first.instance_variable_get(:@edit_observers)).to eq([other])
  end
end

RSpec.describe Roded::Window, "local word movement" do
  it "matches character-wise word navigation at every position including Unicode and blank lines" do
    text = "one!!! two\n\n...\nПривет-world e\u0301 🙂\n"
    lines = text.split("\n", -1)
    buffer = Roded::Buffer.new.load_text(text)
    window = described_class.new(buffer)
    chars = text.each_char.to_a
    positions = lines.each_index.flat_map { |row| (0..lines[row].length).map { |col| { row:, col: } } }
    positions.each do |point|
      offset = lines.take(point[:row]).sum(&:length) + point[:row] + point[:col]
      %i[forward backward].each do |direction|
        window.point = point
        expected = word_reference(chars, offset, direction)
        window.public_send("move_cursor_word_#{direction}")
        expect(window.point).to eq(expected), "#{direction} from #{point}"
      end
    end
  end

  # Intentionally retains the old character-wise algorithm as an independent oracle.
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  def word_reference(chars, offset, direction)
    word = ->(char) { char&.match?(/\A[\p{Alnum}_]\z/) }
    if direction == :forward
      offset += 1 while offset < chars.length && !word.call(chars[offset])
      offset += 1 while offset < chars.length && word.call(chars[offset])
    else
      offset -= 1 while offset.positive? && !word.call(chars[offset - 1])
      offset -= 1 while offset.positive? && word.call(chars[offset - 1])
    end
    parts = chars.take(offset).join.split("\n", -1)
    parts = [""] if parts.empty?
    { row: parts.length - 1, col: parts.last.length }
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
end
# rubocop:enable Metrics/BlockLength
