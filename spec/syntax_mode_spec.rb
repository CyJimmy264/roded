RSpec.describe Roded::Buffer do
  it "selects syntax modes from file extensions and allows explicit changes" do
    expect(described_class.new("app.rb").mode).to eq(:ruby)
    expect(described_class.new("data.json").mode).to eq(:json)
    expect(described_class.new("config.yaml").mode).to eq(:yaml)
    expect(described_class.new("README.md").mode).to eq(:markdown)
    expect(described_class.new("notes.txt").mode).to eq(:plain)

    buffer = described_class.new("sample.rb")
    buffer.insert_text("def answer = 42")
    saved_text = buffer.to_s
    history_size = buffer.instance_variable_get(:@undo_stack).length
    buffer.major_mode = :plain

    expect(buffer.mode).to eq(:plain)
    expect(buffer.to_s).to eq(saved_text)
    expect(buffer.modified?).to be(true)
    expect(buffer.instance_variable_get(:@undo_stack).length).to eq(history_size)
  end
end
