RSpec.describe Roded::Application do
  it "updates cached token spans after edits and undo without changing save state" do
    application = described_class.new
    application.startup
    buffer = application.current_buffer
    buffer.filename = "sample.rb"
    buffer.load_text("def answer = 42")
    spans = application.editor_snapshot[:windows].first[:tokens].flatten
    expect(spans.map { |span| span[:category] }).to include(:keyword, :number)

    buffer.insert_text(" # comment")
    edited_spans = application.editor_snapshot[:windows].first[:tokens].flatten
    expect(edited_spans.map { |span| span[:category] }).to include(:comment)
    expect(buffer.undo).to be(true)

    restored_spans = application.editor_snapshot[:windows].first[:tokens].flatten
    expect(restored_spans.map { |span| span[:category] }).not_to include(:comment)
    expect(buffer.modified?).to be(false)
  end
end
