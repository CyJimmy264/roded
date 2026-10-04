RSpec.describe Roded::Application do
  it "updates cached token spans after edits and undo without changing save state" do
    application = described_class.new
    application.startup
    buffer = application.current_buffer
    buffer.filename = "sample.rb"
    buffer.load_text("def answer = 42")
    spans = application.editor_snapshot[:windows].first[:tokens].flatten
    expect(spans.map { |span| span[:category] }).to include(:keyword, :number)

    buffer.insert_text(" # comment", at: application.current_window.point)
    edited_spans = application.editor_snapshot[:windows].first[:tokens].flatten
    expect(edited_spans.map { |span| span[:category] }).to include(:comment)
    expect(buffer.undo).to be(true)

    restored_spans = application.editor_snapshot[:windows].first[:tokens].flatten
    expect(restored_spans.map { |span| span[:category] }).not_to include(:comment)
    expect(buffer.modified?).to be(false)
  end
end

RSpec.describe Roded::Application, "incomplete Ruby syntax snapshots" do
  it "keeps incomplete multiline spans aligned across edit and undo" do
    application = described_class.new
    application.startup
    buffer = application.current_buffer
    buffer.filename = "sample.rb"
    buffer.load_text("message = \"")
    application.current_window.point = { row: 0, col: buffer.lines.first.length }
    buffer.insert_text("unfinished\nстрока 🙂", at: application.current_window.point)

    edited_tokens = application.editor_snapshot[:windows].first[:tokens]
    expect(edited_tokens.last).to include(hash_including(start: 0, finish: 8, category: :string))
    expect(application.undo).to be(true)

    restored_tokens = application.editor_snapshot[:windows].first[:tokens]
    expect(restored_tokens).to eq([[{ start: 10, finish: 11, category: :string }]])
  end
end

RSpec.describe Roded::Application, "Unicode highlight snapshots" do
  it "computes spans without mutating editor state" do
    application = described_class.new
    application.startup
    buffer = application.current_buffer
    buffer.filename = "sample.rb"
    buffer.load_text("x = \"🙂\"; 42")
    application.current_window.point = { row: 0, col: 7 }
    before = [buffer.to_s, application.current_window.point, buffer.modified?]
    history_size = buffer.instance_variable_get(:@undo_stack).length

    snapshot = application.editor_snapshot

    number = snapshot[:windows].first[:tokens].first.find { |span| span[:category] == :number }
    expect(number).to include(start: 9, finish: 11)
    expect([buffer.to_s, application.current_window.point, buffer.modified?]).to eq(before)
    expect(buffer.instance_variable_get(:@undo_stack).length).to eq(history_size)
  end
end
