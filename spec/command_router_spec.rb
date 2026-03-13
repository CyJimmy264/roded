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

    expect(first).to eq(Roded::Event.new(:noop, {}))
    expect(second).to eq(Roded::Event.new(:quit, {}))
  end

  it "resolves meta bindings through escape prefix" do
    first = router.route("Esc")
    second = router.route("x")

    expect(first).to eq(Roded::Event.new(:noop, {}))
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
end
# rubocop:enable Metrics/BlockLength
