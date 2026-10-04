RSpec.shared_context "routed query replacement" do
  subject(:application) { Roded::Application.new }

  before do
    application.add_frontend(FakeFrontend.new)
    application.startup
    application.current_buffer.load_text("cat dog cat cat")
    application.split_window(:vertical)
  end

  def send_query_key(key)
    application.handle_event(Roded::InputEvent.new(:key, { key: }))
  end

  def submit_query_text(text)
    text.each_char { |key| send_query_key(key) }
    send_query_key("Enter")
  end

  def start_routed_query_replace
    send_query_key("M-%")
    submit_query_text("cat")
    submit_query_text("fox")
  end
end

RSpec.describe Roded::Application, "query replacement confirmation through input" do
  include_context "routed query replacement"

  it "keeps the match confirmation open when rendering is deferred until the end of the input command" do
    start_routed_query_replace

    expect(application.focus).to eq(:minibuffer)
    expect(application.minibuffer.prompt).to eq("Replace? y, n, !, or q: ")
    expect(application.current_buffer.to_s).to eq("cat dog cat cat")
    expect(application.current_window.highlight).to eq(start: { row: 0, col: 0 }, finish: { row: 0, col: 3 })
  end
end

RSpec.describe Roded::Application, "query replace-all through input" do
  include_context "routed query replacement"

  it "replaces all matches through routed keys and restores the shared document with one undo" do
    start_routed_query_replace
    submit_query_text("!")

    expect(application.focus).to eq(:buffer)
    expect(application.current_buffer.to_s).to eq("fox dog fox fox")
    expect(application.windows.map(&:highlight)).to eq([nil, nil])

    send_query_key("C-/")
    expect(application.current_buffer.to_s).to eq("cat dog cat cat")
    expect(application.windows.map { |window| window.buffer.to_s }).to eq(["cat dog cat cat"] * 2)
  end
end
