RSpec.describe "editor message contracts" do
  it "distinguishes incoming facts from routed editor commands and UI updates" do
    input = Roded::InputEvent.new(:key, { key: "C-n" })
    command = Roded::EditorCommand.new(:move_down, {}, :qt, 42)
    update = Roded::Command.new(:render, {})

    expect(input).to be_a(Roded::InputEvent)
    expect(command).to be_a(Roded::EditorCommand)
    expect(update).to be_a(Roded::UIUpdate)
    expect(Roded::Event).to equal(Roded::InputEvent)
  end

  it "rejects input facts at the editor command handler boundary" do
    handler = Roded::CommandHandler.new(Object.new)

    expect do
      handler.handle(Roded::InputEvent.new(:move_down, {}))
    end.to raise_error(ArgumentError, /expected EditorCommand/)
  end

  it "rejects editor commands at the application input boundary" do
    application = Roded::Application.new

    expect do
      application.handle_event(Roded::EditorCommand.new(:move_down, {}, nil, nil))
    end.to raise_error(ArgumentError, /expected InputEvent/)
  end
end

RSpec.describe Roded::UIUpdate do
  it "copies and deeply freezes payloads before frontend delivery" do
    payload = { text: +"hello", nested: [+"world"] }
    update = described_class.new(:message, payload)
    payload[:text].replace("changed")
    payload[:nested].first.replace("changed")
    payload[:nested] << "extra"

    expect(update.payload).to eq(text: "hello", nested: ["world"])
    expect(update.payload).to be_frozen
    expect(update.payload.fetch(:text)).to be_frozen
    expect(update.payload.fetch(:nested)).to be_frozen
    expect(update.payload.fetch(:nested).first).to be_frozen
  end

  it "rejects unsupported mutable payload values" do
    expect do
      described_class.new(:message, { object: Object.new })
    end.to raise_error(TypeError, /unsupported mutable UI update value/)
  end
end

RSpec.describe Roded::UIUpdate, "shared immutable payload validation" do
  it "reuses deeply immutable containers without trusting a frozen outer container with mutable children" do
    lines = ["original".freeze].freeze
    frozen = { lines: }.freeze
    first = described_class.new(:render, frozen)
    expect(first.payload).to equal(frozen)
    expect(described_class.new(:render, frozen).payload).to equal(frozen)
    mutable_line = +"mutable"
    shallow = { lines: [mutable_line] }.freeze
    copied = described_class.new(:render, shallow)
    mutable_line << " changed"
    expect(copied.payload[:lines]).to eq(["mutable"])
    expect(copied.payload[:lines]).to be_frozen
  end

  it "validates shared immutable snapshots from multiple frontend threads" do
    payload = { lines: Array.new(1500, "text".freeze).freeze }.freeze
    results = Queue.new
    threads = Array.new(4) do
      Thread.new { 20.times { results << described_class.new(:render, payload).payload } }
    end
    threads.each(&:join)
    expect(Array.new(80) { results.pop }).to all(equal(payload))
  end
end
