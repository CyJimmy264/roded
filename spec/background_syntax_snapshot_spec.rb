require "timeout"

module BackgroundSyntaxSpecSupport
  def ruby_application
    Roded::Application.new.tap do |app|
      app.startup
      app.current_buffer.major_mode = :ruby
      app.current_buffer.load_text(Array.new(1500, 'value = "🙂"; 42 # comment').join("\n"))
      app.current_window.point = { row: 750, col: 9 }
      app.editor_snapshot
    end
  end

  def settle_syntax(app)
    Timeout.timeout(10) do
      app.handle_event(app.instance_variable_get(:@event_queue).pop) while app.syntax_highlighting_pending?
    end
  end
end

RSpec.describe Roded::Application, "background heredoc history" do
  include BackgroundSyntaxSpecSupport

  it "recovers the latest Unicode heredoc colors after structural edits and undo" do
    app = ruby_application
    text = ["value = <<~DOC", *Array.new(1498, "  body 🙂"), "DOC"].join("\n")
    app.current_buffer.load_text(text)
    app.current_window.point = { row: 750, col: 4 }
    app.handle_event(Roded::InputEvent.new(:enter, {}))
    app.handle_event(Roded::InputEvent.new(:undo, {}))
    app.handle_event(Roded::InputEvent.new(:insert_char, { char: "界" }))
    settle_syntax(app)
    expected = Roded::SyntaxHighlighter.new.spans(:ruby, app.current_buffer.lines)
    expect(app.editor_snapshot[:windows].first[:tokens]).to eq(expected)
    expect(expected[750]).to include(hash_including(category: :string))
  ensure
    app&.shutdown_syntax_highlighting
  end
end

RSpec.describe Roded::Application, "background syntax snapshots" do
  include BackgroundSyntaxSpecSupport

  it "publishes edits immediately and later restores complete multiline lexical context" do
    app = ruby_application
    frontend = FakeFrontend.new
    app.add_frontend(frontend)
    highlighter = app.instance_variable_get(:@syntax_highlighter)
    expect(highlighter).not_to receive(:spans)
    app.current_window.point = { row: 750, col: 8 }
    app.handle_event(Roded::InputEvent.new(:delete, {}))
    expect(app.current_buffer.lines[750]).to start_with("value = 🙂\"; 42")
    expect(app.editor_snapshot[:windows].first[:tokens][750]).to eq([])
    expect(app.syntax_highlighting_pending?).to be(true)
    settle_syntax(app)
    expected = Roded::SyntaxHighlighter.new.spans(:ruby, app.current_buffer.lines)
    expect(app.editor_snapshot[:windows].first[:tokens]).to eq(expected)
    expect(frontend.commands.last.payload[:editor_snapshot][:windows].first[:tokens]).to eq(expected)
  ensure
    app&.shutdown_syntax_highlighting
  end
end

RSpec.describe Roded::Application, "superseded syntax snapshots" do
  include BackgroundSyntaxSpecSupport

  it "rejects stale edits and publishes the latest revision in every view" do
    app = ruby_application
    app.split_window(:vertical)
    app.handle_event(Roded::InputEvent.new(:insert_char, { char: "X" }))
    stale = { id: 1, buffer_id: app.current_buffer.object_id, revision: app.current_buffer.revision,
              changes: [[750, [], "invalid"]] }
    app.handle_event(Roded::InputEvent.new(:insert_char, { char: "Y" }))
    app.handle_event(Roded::InputEvent.new(:syntax_result, stale))
    expect(app.syntax_highlighting_pending?).to be(true)
    settle_syntax(app)
    expected = Roded::SyntaxHighlighter.new.spans(:ruby, app.current_buffer.lines)
    frames = app.editor_snapshot[:windows]
    expect(frames.map { |frame| frame[:tokens] }).to eq([expected, expected])
    expect(frames.first[:tokens]).to equal(frames.last[:tokens])
  ensure
    app&.shutdown_syntax_highlighting
  end
end

RSpec.describe Roded::Application, "syntax mode changes" do
  include BackgroundSyntaxSpecSupport

  it "cancels pending Ruby work when a buffer changes mode" do
    app = ruby_application
    app.handle_event(Roded::InputEvent.new(:insert_char, { char: "X" }))
    stale = { id: 1, buffer_id: app.current_buffer.object_id, revision: app.current_buffer.revision,
              changes: [[750, [{ start: 0, finish: 1, category: :keyword }], "invalid"]] }
    app.change_major_mode(:plain)
    app.handle_event(Roded::InputEvent.new(:syntax_result, stale))
    expect(app.syntax_highlighting_pending?).to be(false)
    expect(app.editor_snapshot[:windows].first[:tokens]).to all(be_empty)
  ensure
    app&.shutdown_syntax_highlighting
  end
end
