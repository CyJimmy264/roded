require "timeout"

module RubyReplSpecHelpers
  def setup_repl_application(application)
    application.startup
    target = Roded::Buffer.new("target")
    application.add_buffer(target)
    application.open_ruby_repl
    [target, application.current_buffer]
  end

  def push_keys(application, *keys)
    keys.each { |key| application.push_event(Roded::Event.new(:key, { key: })) }
  end
end

RSpec.configure { |config| config.include(RubyReplSpecHelpers) }

RSpec.describe Roded::Application, "core-queue API" do
  it "uses the core event loop for Ruby REPL mutations" do
    application = described_class.new
    target, repl = setup_repl_application(application)
    code = [
      'editor.switch_buffer("target")',
      'editor.insert_text("added")',
      'editor.execute_command("undo")',
      'editor.execute_command("redo")'
    ].join("; ")
    repl.insert_text(code)
    application.current_window.point = repl.cursor_pos

    worker = Thread.new { application.send(:main_loop) }
    push_keys(application, "C-c", "C-c")
    Timeout.timeout(3) { sleep 0.01 until target.to_s == "added" && repl.to_s.include?("=> true") }

    expect(target.to_s).to eq("added")
    expect(repl.to_s).to include(code, "=> true", "> ")
  ensure
    application&.push_event(Roded::Event.new(:quit, {}))
    worker&.join(2)
    application&.send(:shutdown_ruby_repl)
  end
end

RSpec.describe Roded::Application, "core event loop ownership" do
  it "runs editor API commands on the core event loop thread" do
    application = described_class.new
    api = Roded::RubyEditorAPI.new(application)
    execution_threads = Queue.new
    worker = Thread.new { application.send(:main_loop) }
    Timeout.timeout(3) { sleep 0.01 until application.instance_variable_get(:@core_thread) }

    api.register_command("record-thread") { execution_threads << Thread.current }
    api.execute_command("record-thread")

    expect(Timeout.timeout(3) { execution_threads.pop }).to equal(worker)
  ensure
    application&.push_event(Roded::Event.new(:quit, {}))
    worker&.join(2)
  end
end

RSpec.describe Roded::Application, "immutable editor API" do
  it "returns immutable snapshots and ignores edits to readonly documents" do
    application = described_class.new
    application.startup
    readonly = Roded::Buffer.new("locked")
    readonly.load_text("unchanged")
    readonly.readonly = true
    application.add_buffer(readonly)
    api = Roded::RubyEditorAPI.new(application)

    api.switch_buffer("locked")
    snapshot = api.current_buffer
    api.insert_text("!")

    expect(snapshot[:readonly]).to be(true)
    expect(snapshot[:text]).to eq("unchanged")
    expect(snapshot).to be_frozen
    expect(api.windows.first).to be_frozen
    expect(readonly.to_s).to eq("unchanged")
  end
end

RSpec.describe Roded::Application, "REPL interface" do
  it "opens the in-process REPL as a writable buffer" do
    application = described_class.new
    application.startup

    %w[C-c r r].each do |key|
      application.handle_event(Roded::Event.new(:key, { key: }))
    end

    expect(application.current_buffer.name).to eq("*ruby*")
    expect(application.current_buffer.readonly).to be(false)
    expect(application.current_buffer.to_s).to include("C-c C-c evaluates", "> ")
  end

  it "cycles through completed input history" do
    application = described_class.new
    application.startup
    application.open_ruby_repl
    session = application.instance_variable_get(:@ruby_repl_session)
    session.start_evaluation?("1 + 1")
    application.handle_event(application.instance_variable_get(:@event_queue).pop)

    application.cycle_ruby_repl_history(-1)

    expect(application.current_buffer.lines.last).to eq("> 1 + 1")
  ensure
    application&.send(:shutdown_ruby_repl)
  end
end

RSpec.describe Roded::Application, "REPL command registration" do
  it "runs a registered command from its key binding and M-x" do
    application = described_class.new
    target, repl = setup_repl_application(application)
    repl.insert_text(
      'editor.register_command("insert-star", binding: "C-c t") { |api| ' \
      'api.switch_buffer("target"); api.insert_text("*") }'
    )
    application.current_window.point = repl.cursor_pos

    worker = Thread.new { application.send(:main_loop) }
    push_keys(application, "C-c", "C-c")
    Timeout.timeout(3) { sleep 0.01 until repl.to_s.include?("=> ") }
    push_keys(application, "C-c", "t")
    Timeout.timeout(3) { sleep 0.01 until target.to_s == "*" }
    %w[Esc x i n s e r t - s t a r Enter].each do |key|
      application.push_event(Roded::Event.new(:key, { key: }))
    end
    Timeout.timeout(3) { sleep 0.01 until target.to_s == "**" }
  ensure
    application&.push_event(Roded::Event.new(:quit, {}))
    worker&.join(2)
    application&.send(:shutdown_ruby_repl)
  end
end

RSpec.describe Roded::Application, "documented Ruby API" do
  it "saves a live buffer through the editor facade" do
    application = described_class.new
    application.startup
    buffer = application.current_buffer
    buffer.insert_text("saved from Ruby")
    api = Roded::RubyEditorAPI.new(application)
    path = File.join(Dir.mktmpdir, "notes.txt")

    result = api.save_file(path)

    expect(result.path).to eq(path)
    expect(File.read(path)).to eq("saved from Ruby")
    expect(api.buffers.map { |item| item[:name] }).to include("*scratch*")
    expect(buffer.modified?).to be(false)
  end
end
