# rubocop:disable Metrics/BlockLength
RSpec.describe Roded::CommandRouter do
  subject(:router) { described_class.new(keymap) }

  let(:keymap) { Roded::Keymap.new(Roded::Keymap::DEFAULT) }

  it "routes direct key bindings from the keymap" do
    event = router.route("C-n")

    expect(event).to eq(editor_command(:move_down))
    expect(router.route("Tab")).to eq(editor_command(:indent))
  end

  it "resolves C-x prefixed bindings across multiple keys" do
    first = router.route("C-x")
    second = router.route("C-c")

    expect(first).to eq(editor_command(:prefix_pending, { prefix: "C-x" }))
    expect(second).to eq(editor_command(:request_quit))
  end

  it "routes window split and navigation bindings" do
    expect(route_sequence("C-x", "2")).to eq(editor_command(:split_horizontal))
    expect(route_sequence("C-x", "3")).to eq(editor_command(:split_vertical))
    expect(route_sequence("C-x", "o")).to eq(editor_command(:other_window))
    expect(route_sequence("C-x", "0")).to eq(editor_command(:delete_window))
    expect(route_sequence("C-x", "1")).to eq(editor_command(:delete_other_windows))
  end

  it "routes Super aliases to existing editor actions" do
    expect(router.route("M-s-j")).to eq(editor_command(:save_buffer))
    expect(router.route("M-s-k")).to eq(editor_command(:kill_buffer))
    expect(router.route("M-s-c")).to eq(editor_command(:delete_window))
    expect(router.route("s-w")).to eq(editor_command(:other_window))
    expect(router.route("s-,")).to eq(editor_command(:previous_buffer))
    expect(router.route("s-.")).to eq(editor_command(:next_buffer))
    expect(router.route("C-<")).to eq(editor_command(:previous_buffer))
    expect(router.route("C->")).to eq(editor_command(:next_buffer))
    expect(router.route("s-Left")).to eq(editor_command(:shrink_window_horizontally))
    expect(router.route("s-Right")).to eq(editor_command(:enlarge_window_horizontally))
  end

  it "resolves meta bindings through escape prefix" do
    first = router.route("Esc")
    second = router.route("x")

    expect(first).to eq(editor_command(:prefix_pending, { prefix: "Esc" }))
    expect(second).to eq(editor_command(:start_command))
  end

  it "turns plain characters into insert events" do
    event = router.route("a")

    expect(event).to eq(editor_command(:insert_char, { char: "a" }))
    expect(router.route(" ")).to eq(editor_command(:insert_char, { char: " " }))
  end

  it "returns noop for unknown non-insertable keys" do
    event = router.route("F1")

    expect(event).to eq(editor_command(:noop))
  end

  it "returns nil for nil input" do
    expect(router.route(nil)).to be_nil
  end

  it "keeps pending prefixes separate for independent input sources" do
    first = router.route("C-x", source_id: :first)
    second = router.route("C-z", source_id: :second)
    completed = router.route("C-c", source_id: :first)

    expect(first.type).to eq(:prefix_pending)
    expect(second).to eq(editor_command(:noop, {}, source_id: :second))
    expect(completed).to eq(editor_command(:request_quit, {}, source_id: :first))
  end

  it "resolves arbitrary multi-key sequences from the keymap" do
    custom_map = Roded::Keymap.new(Roded::Keymap::DEFAULT.merge(
                                     "C-c r r" => { type: :ruby_repl }
                                   ))
    custom_router = described_class.new(custom_map)

    expect(custom_router.route("C-c").type).to eq(:prefix_pending)
    expect(custom_router.route("r").type).to eq(:prefix_pending)
    expect(custom_router.route("r")).to eq(editor_command(:ruby_repl))
  end

  def route_sequence(*keys)
    keys.map { |key| router.route(key) }.last
  end

  it "resolves multi-key Meta sequences" do
    expect(router.route("Esc").type).to eq(:prefix_pending)
    expect(router.route("g").type).to eq(:prefix_pending)
    expect(router.route("g").type).to eq(:goto_line)
  end

  it "routes the project-file picker sequence" do
    expect(route_sequence("C-c", "p", "f")).to eq(editor_command(:project_files))
  end

  it "preserves source and view context on routed editor commands" do
    command = router.route("C-n", source_id: :qt, view_id: 42)

    expect(command).to eq(editor_command(:move_down, {}, source_id: :qt, view_id: 42))
  end

  def editor_command(type, payload = {}, source_id: nil, view_id: nil)
    Roded::EditorCommand.new(type, payload, source_id, view_id)
  end
end
# rubocop:enable Metrics/BlockLength
