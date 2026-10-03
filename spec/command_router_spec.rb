# rubocop:disable Metrics/BlockLength
RSpec.describe Roded::CommandRouter do
  subject(:router) { described_class.new(keymap) }

  let(:keymap) { Roded::Keymap.new(Roded::Keymap::DEFAULT) }

  it "routes direct key bindings from the keymap" do
    event = router.route("C-n")

    expect(event).to eq(Roded::Event.new(:move_down, {}))
  end

  it "resolves C-x prefixed bindings across multiple keys" do
    first = router.route("C-x")
    second = router.route("C-c")

    expect(first).to eq(Roded::Event.new(:prefix_pending, { prefix: "C-x" }))
    expect(second).to eq(Roded::Event.new(:request_quit, {}))
  end

  it "resolves meta bindings through escape prefix" do
    first = router.route("Esc")
    second = router.route("x")

    expect(first).to eq(Roded::Event.new(:prefix_pending, { prefix: "Esc" }))
    expect(second).to eq(Roded::Event.new(:start_command, {}))
  end

  it "turns plain characters into insert events" do
    event = router.route("a")

    expect(event).to eq(Roded::Event.new(:insert_char, { char: "a" }))
  end

  it "returns noop for unknown non-insertable keys" do
    event = router.route("F1")

    expect(event).to eq(Roded::Event.new(:noop, {}))
  end

  it "returns nil for nil input" do
    expect(router.route(nil)).to be_nil
  end

  it "keeps pending prefixes separate for independent input sources" do
    first = router.route("C-x", source_id: :first)
    second = router.route("C-c", source_id: :second)
    completed = router.route("C-c", source_id: :first)

    expect(first.type).to eq(:prefix_pending)
    expect(second).to eq(Roded::Event.new(:noop, {}))
    expect(completed).to eq(Roded::Event.new(:request_quit, {}))
  end

  it "resolves arbitrary multi-key sequences from the keymap" do
    custom_map = Roded::Keymap.new(Roded::Keymap::DEFAULT.merge(
                                     "C-c r r" => { type: :ruby_repl }
    ))
    custom_router = described_class.new(custom_map)

    expect(custom_router.route("C-c").type).to eq(:prefix_pending)
    expect(custom_router.route("r").type).to eq(:prefix_pending)
    expect(custom_router.route("r")).to eq(Roded::Event.new(:ruby_repl, {}))
  end
end
# rubocop:enable Metrics/BlockLength
