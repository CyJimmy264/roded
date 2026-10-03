require "tempfile"
require "timeout"

# rubocop:disable Metrics/BlockLength
RSpec.describe Roded::Application do
  subject(:application) { described_class.new }

  let(:frontend) { FakeFrontend.new }

  before do
    application.instance_variable_set(:@frontends, [frontend])
  end

  it "opens the command minibuffer from M-x and broadcasts its state" do
    application.handle_event(Roded::Event.new(:key, { key: "Esc" }))
    application.handle_event(Roded::Event.new(:key, { key: "x" }))

    expect(application.focus).to eq(:minibuffer)
    expect(frontend.focus).to eq(:minibuffer)
    expect(frontend.commands).to include(
      Roded::Command.new(:minibuffer_render, { prompt: "M-x ", text: "", cursor: 0 })
    )
    expect(frontend.commands.last.type).to eq(:picker_render)
    expect(frontend.commands.last.payload[:candidates]).to include("quit", "redo")
  end

  it "submits M-x quit through routed key events" do
    %w[Esc x q u i t Enter].each do |key|
      application.handle_event(Roded::Event.new(:key, { key: key }))
    end

    expect(application.focus).to eq(:buffer)
    expect(frontend.focus).to eq(:buffer)
    expect(frontend.commands).to include(Roded::Command.new(:quit, {}))
    expect(application.instance_variable_get(:@stop_requested)).to be(true)
  end

  it "filters the M-x picker and accepts the selected command" do
    application.startup
    %w[Esc x u n d o Enter].each do |key|
      application.handle_event(Roded::Event.new(:key, { key: }))
    end

    expect(application.focus).to eq(:buffer)
    expect(application.instance_variable_get(:@picker)).to be_nil
    picker_commands = frontend.commands.select { |command| command.type == :picker_render }
    expect(picker_commands.last.payload[:candidates]).to eq(["undo"])
  end

  it "moves the selected M-x candidate with C-n and C-p" do
    application.start_minibuffer(:command, "M-x ")
    application.minibuffer.insert_char("u")
    application.refresh_picker
    expect(application.selected_picker_value).to eq("kill-buffer")
    application.handle_event(Roded::Event.new(:key, { key: "C-n" }))
    expect(application.selected_picker_value).to eq("next-buffer")
    application.handle_event(Roded::Event.new(:key, { key: "C-p" }))
    expect(application.selected_picker_value).to eq("kill-buffer")
  end

  it "executes one registered command through M-x and its key binding" do
    application.startup
    calls = 0
    application.register_command("count-call", binding: "C-c r g", description: "Count a call") do |editor|
      calls += 1
      editor.current_buffer.insert_char("x")
    end

    %w[C-c r g].each do |key|
      application.handle_event(Roded::Event.new(:key, { key: }))
    end
    application.process_command("count-call")

    expect(calls).to eq(2)
    expect(application.current_buffer.to_s).to eq("xx")
    expect(application.command_names).to include("count-call", "undo", "redo")
    expect(application.command_names).to be_frozen
    custom_command = application.command_catalog.find { |command| command[:name] == "count-call" }
    expect(custom_command).to eq(name: "count-call", description: "Count a call")
    expect(custom_command).to be_frozen
  end

  it "runs undo and redo commands against the active buffer" do
    application.startup
    buffer = application.current_buffer
    buffer.insert_char("a")

    application.process_command("undo")
    expect(buffer.to_s).to eq("")

    application.process_command("redo")
    expect(buffer.to_s).to eq("a")
    expect(frontend.commands.last.type).to eq(:render)
    expect(frontend.commands.last.payload[:editor_snapshot][:windows].first[:text]).to eq("a")
  end

  it "inserts a paste as one multiline edit" do
    application.startup
    buffer = application.current_buffer

    application.handle_event(Roded::Event.new(:paste, { text: "first\nsecond" }))

    expect(buffer.lines).to eq(%w[first second])
    expect(buffer.undo).to be(true)
    expect(buffer.to_s).to eq("")
  end

  it "cuts and yanks a marked region with undoable buffer edits" do
    application.startup
    buffer = application.current_buffer
    buffer.lines = ["abcdef"]
    application.current_window.point = { row: 0, col: 1 }

    application.handle_event(Roded::Event.new(:key, { key: "C-SPC" }))
    application.handle_event(Roded::Event.new(:key, { key: "C-f" }))
    application.handle_event(Roded::Event.new(:key, { key: "C-w" }))

    expect(buffer.to_s).to eq("acdef")
    expect(application.kill_ring.last).to eq("b")
    expect(application.current_window.mark).to be_nil
    expect(buffer.undo).to be(true)
    expect(buffer.to_s).to eq("abcdef")

    application.handle_event(Roded::Event.new(:key, { key: "C-y" }))
    expect(buffer.to_s).to eq("abbcdef")
  end

  it "replaces the last yank from the kill ring and keeps it undoable" do
    application.startup
    buffer = application.current_buffer
    buffer.load_text("||")
    application.current_window.point = { row: 0, col: 1 }
    application.kill_ring.push("first")
    application.kill_ring.break_sequence
    application.kill_ring.push("second")

    application.handle_event(Roded::Event.new(:key, { key: "C-y" }))
    expect(buffer.to_s).to eq("|second|")
    application.handle_event(Roded::Event.new(:key, { key: "Esc" }))
    application.handle_event(Roded::Event.new(:key, { key: "y" }))
    application.handle_event(Roded::Event.new(:key, { key: "C-n" }))
    application.handle_event(Roded::Event.new(:key, { key: "Enter" }))
    expect(buffer.to_s).to eq("|first|")

    expect(buffer.undo).to be(true)
    expect(buffer.to_s).to eq("|second|")
    expect(buffer.undo).to be(true)
    expect(buffer.to_s).to eq("||")
  end

  it "keeps buffer positions in the active window while switching buffers" do
    application.startup
    window = application.current_window
    application.current_buffer.lines = ["scratch"]
    window.point = { row: 0, col: 2 }
    second = Roded::Buffer.new("second")
    second.lines = ["other"]
    application.add_buffer(second)

    application.switch_buffer("second")
    expect(window.buffer).to equal(second)
    window.point = { row: 0, col: 4 }
    application.switch_buffer("*scratch*")
    expect(window.point).to eq({ row: 0, col: 2 })
    application.switch_buffer("second")
    expect(window.point).to eq({ row: 0, col: 4 })
    expect(application.current_buffer.cursor_pos).to eq({ row: 0, col: 4 })
  end

  it "keeps the active window point synchronized with routed edits" do
    application.startup

    application.handle_event(Roded::Event.new(:key, { key: "x" }))

    expect(application.current_window.point).to eq({ row: 0, col: 1 })
    expect(application.current_buffer.cursor_pos).to eq({ row: 0, col: 1 })
  end

  it "transforms the other view point and mark on edits and undo" do
    application.startup
    buffer = application.current_buffer
    buffer.lines = ["abcdef"]
    first = application.current_window
    first.point = { row: 0, col: 5 }
    first.mark = { row: 0, col: 3 }
    second = application.split_window(:vertical)
    second.point = { row: 0, col: 1 }

    application.handle_event(Roded::Event.new(:key, { key: "X" }))

    expect(buffer.to_s).to eq("aXbcdef")
    expect(first.point).to eq({ row: 0, col: 6 })
    expect(first.mark).to eq({ row: 0, col: 4 })
    application.undo

    expect(buffer.to_s).to eq("abcdef")
    expect(first.point).to eq({ row: 0, col: 5 })
    expect(first.mark).to eq({ row: 0, col: 3 })
  end

  it "splits, switches, and closes editor windows without closing their buffer" do
    application.startup
    buffer = application.current_buffer
    buffer.lines = ["shared text"]
    application.current_window.point = { row: 0, col: 2 }
    first = application.current_window

    second = application.split_window(:vertical)
    expect(application.windows).to eq([first, second])
    expect(second.buffer).to equal(buffer)
    expect(second.point).to eq({ row: 0, col: 2 })
    second.point = { row: 0, col: 5 }
    snapshot = application.editor_snapshot
    expect(snapshot[:windows].map { |item| item[:text] }).to eq(["shared text", "shared text"])
    expect(snapshot[:tree][:direction]).to eq(:vertical)
    expect(snapshot[:windows].first[:point]).to be_frozen
    expect(snapshot[:windows].first[:text]).to be_frozen

    application.other_window
    expect(application.current_window).to equal(first)
    expect(first.point).to eq({ row: 0, col: 2 })
    application.delete_window
    expect(application.windows).to eq([second])
    expect(application.buffers).to include(buffer)
  end

  it "keeps only the active window when deleting other windows" do
    application.startup
    first = application.current_window
    application.split_window(:horizontal)
    active = application.current_window

    application.delete_other_windows

    expect(application.windows).to eq([active])
    expect(application.current_window).to equal(active)
    expect(application.windows).not_to include(first)
  end

  it "opens a file and renders the loaded buffer" do
    Tempfile.create("roded-open") do |file|
      file.write("alpha\nbeta\n")
      file.flush

      application.open_file(file.path)

      expect(application.current_buffer.filename).to eq(file.path)
      expect(application.current_buffer.lines).to eq(%w[alpha beta])
      expect(application.current_buffer.cursor_pos).to eq({ row: 0, col: 0 })
      expect(frontend.buffers.last).to eq(application.current_buffer)
      expect(frontend.renders.last).to eq(application.current_buffer)
      expect(frontend.messages.last).to eq("File '#{file.path}' opened.")
    end
  end

  it "creates a new buffer for a missing file without creating its parent" do
    Dir.mktmpdir("roded-new-file") do |directory|
      path = File.join(directory, "new.txt")
      application.open_file(path)

      expect(application.current_buffer.filename).to eq(path)
      expect(application.current_buffer.to_s).to eq("")
      expect(File.exist?(path)).to be(false)
      application.current_buffer.insert_char("x")
      application.save_file(path)
      expect(File.binread(path)).to eq("x")
    end
  end

  it "reuses an open file buffer through different path spellings" do
    Dir.mktmpdir("roded-path-alias") do |directory|
      path = File.join(directory, "file.txt")
      alias_path = File.join(directory, "alias.txt")
      File.write(path, "text")
      File.symlink(path, alias_path)

      application.open_file(path)
      original = application.current_buffer
      application.open_file(alias_path)

      expect(application.current_buffer).to equal(original)
      expect(application.buffers.count { |buffer| buffer.filename == path }).to eq(1)
    end
  end

  it "opens all command-line paths and starts with a writable scratch buffer when none are given" do
    Dir.mktmpdir("roded-startup") do |directory|
      first = File.join(directory, "first.txt")
      second = File.join(directory, "second.txt")
      File.write(first, "one")
      File.write(second, "two")

      application.startup([first, second])

      expect(application.buffers.map(&:filename)).to eq([first, second])
      expect(application.current_buffer.filename).to eq(second)
      expect(application.instance_variable_get(:@windows).length).to eq(1)
    end

    scratch_app = described_class.new
    scratch_app.startup
    expect(scratch_app.current_buffer.name).to eq("*scratch*")
    expect(scratch_app.current_buffer.readonly).to be(false)
  end

  it "cycles through open buffers and switches by exact path from C-x b" do
    Tempfile.create("roded-switch-one") do |first|
      Tempfile.create("roded-switch-two") do |second|
        application.open_file(first.path)
        first_buffer = application.current_buffer
        application.open_file(second.path)
        second_buffer = application.current_buffer

        application.previous_buffer
        expect(application.current_buffer).to equal(first_buffer)
        application.next_buffer
        expect(application.current_buffer).to equal(second_buffer)

        ["C-x", "b", *first.path.chars, "Enter"].each do |key|
          application.handle_event(Roded::Event.new(:key, { key: }))
        end
        expect(application.current_buffer).to equal(first_buffer)
      end
    end
  end

  it "prompts for a path when saving an unnamed buffer with C-x C-s" do
    buffer = Roded::Buffer.new("*scratch*")
    buffer.insert_char("scratch")
    application.add_buffer(buffer)
    path = File.join(Dir.tmpdir, "roded-save-key-#{Process.pid}-#{object_id}.txt")

    %w[C-x C-s].each { |key| application.handle_event(Roded::Event.new(:key, { key: })) }
    expect(application.focus).to eq(:minibuffer)
    answer_minibuffer(application, path)

    expect(File.binread(path)).to eq("scratch")
    expect(buffer.filename).to eq(path)
    expect(buffer.modified?).to be(false)
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  it "kills clean buffers but keeps a writable scratch buffer available" do
    buffer = Roded::Buffer.new("temporary")
    application.add_buffer(buffer)

    application.kill_current_buffer

    expect(application.current_buffer.name).to eq("*scratch*")
    expect(application.buffers.length).to eq(1)
    expect(application.current_buffer.readonly).to be(false)
  end

  it "asks before killing a buffer with unsaved changes" do
    buffer = Roded::Buffer.new("temporary")
    buffer.insert_char("x")
    application.add_buffer(buffer)

    application.kill_current_buffer

    expect(application.current_buffer).to equal(buffer)
    expect(application.buffers).to include(buffer)
    expect(application.focus).to eq(:minibuffer)
    answer_minibuffer(application, "cancel")
    expect(application.current_buffer).to equal(buffer)
    expect(buffer.modified?).to be(true)
  end

  it "saves a dirty buffer before killing it when requested" do
    Tempfile.create("roded-kill-save") do |file|
      file.write("original")
      file.flush
      application.open_file(file.path)
      buffer = application.current_buffer
      buffer.insert_char("x")

      application.kill_current_buffer
      answer_minibuffer(application, "save")

      expect(File.binread(file.path)).to eq("xoriginal")
      expect(application.current_buffer.name).to eq("*scratch*")
      expect(application.buffers).not_to include(buffer)
    end
  end

  it "cancels close confirmation through C-g" do
    buffer = Roded::Buffer.new("dirty")
    buffer.insert_char("x")
    application.add_buffer(buffer)
    application.request_quit

    application.handle_event(Roded::Event.new(:key, { key: "C-g" }))

    expect(application.focus).to eq(:buffer)
    expect(application.instance_variable_get(:@stop_requested)).to be(false)
    expect(buffer.modified?).to be(true)
  end

  it "cancels a quit confirmation without losing buffer edits" do
    buffer = Roded::Buffer.new("dirty")
    buffer.insert_char("x")
    application.add_buffer(buffer)

    application.request_quit
    answer_minibuffer(application, "cancel")

    expect(application.instance_variable_get(:@stop_requested)).to be(false)
    expect(buffer.modified?).to be(true)
  end

  it "discards edited buffers only after the user confirms quit" do
    buffer = Roded::Buffer.new("dirty")
    buffer.insert_char("x")
    application.add_buffer(buffer)

    application.request_quit
    answer_minibuffer(application, "discard")

    expect(application.instance_variable_get(:@stop_requested)).to be(true)
    expect(buffer.to_s).to eq("x")
  end

  it "saves every dirty buffer before quitting when requested" do
    Tempfile.create("roded-save-on-quit-one") do |first|
      Tempfile.create("roded-save-on-quit-two") do |second|
        first.write("first")
        first.flush
        second.write("second")
        second.flush
        application.open_file(first.path)
        first_buffer = application.current_buffer
        first_buffer.insert_char("x")
        application.open_file(second.path)
        second_buffer = application.current_buffer
        second_buffer.insert_char("y")

        application.request_quit
        answer_minibuffer(application, "save")

        expect(File.binread(first.path)).to eq("xfirst")
        expect(File.binread(second.path)).to eq("ysecond")
        expect(first_buffer.modified?).to be(false)
        expect(second_buffer.modified?).to be(false)
        expect(application.instance_variable_get(:@stop_requested)).to be(true)
      end
    end
  end

  it "asks for a path when saving an unnamed buffer during quit" do
    buffer = Roded::Buffer.new("*scratch*")
    buffer.insert_char("scratch text")
    application.add_buffer(buffer)
    path = File.join(Dir.tmpdir, "roded-save-#{Process.pid}-#{object_id}.txt")

    application.request_quit
    answer_minibuffer(application, "save")
    expect(application.focus).to eq(:minibuffer)
    answer_minibuffer(application, path)

    expect(File.binread(path)).to eq("scratch text")
    expect(application.instance_variable_get(:@stop_requested)).to be(true)
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  it "keeps the editor open if a close save encounters a disk conflict" do
    Tempfile.create("roded-conflict-on-quit") do |file|
      file.write("original")
      file.flush
      application.open_file(file.path)
      buffer = application.current_buffer
      buffer.insert_char("x")
      File.write(file.path, "external")

      application.request_quit
      answer_minibuffer(application, "save")
      expect(application.focus).to eq(:minibuffer)
      answer_minibuffer(application, "cancel")

      expect(application.instance_variable_get(:@stop_requested)).to be(false)
      expect(buffer.modified?).to be(true)
      expect(File.binread(file.path)).to eq("external")
    end
  end

  it "synchronizes a late frontend to the active buffer" do
    Tempfile.create("roded-late-frontend") do |file|
      file.write("current")
      file.flush
      application.open_file(file.path)
      late_frontend = FakeFrontend.new

      application.add_frontend(late_frontend)

      expect(late_frontend.buffers).to include(application.current_buffer)
      expect(late_frontend.renders.last).to eq(application.current_buffer)
    end
  end

  it "opens and edits an empty file" do
    Tempfile.create("roded-empty") do |file|
      application.open_file(file.path)

      expect(application.current_buffer.lines).to eq([""])
      application.current_buffer.insert_char("x")
      application.save_file(file.path)
      expect(File.binread(file.path)).to eq("x")
    end
  end

  it "preserves file line endings and a final newline on open and save" do
    Tempfile.create("roded-roundtrip") do |file|
      file.binmode
      file.write("alpha\r\nbeta\r\n")
      file.flush

      application.open_file(file.path)
      application.save_file(file.path)

      expect(File.binread(file.path)).to eq("alpha\r\nbeta\r\n")
    end
  end

  it "keeps edits when the open file changes on disk before saving" do
    Tempfile.create("roded-conflict") do |file|
      file.write("original")
      file.flush
      application.open_file(file.path)
      application.current_buffer.insert_char("x")
      File.write(file.path, "external")

      application.save_file(file.path)

      expect(application.focus).to eq(:minibuffer)
      answer_minibuffer(application, "cancel")
      expect(File.binread(file.path)).to eq("external")
      expect(application.current_buffer.to_s).to eq("xoriginal")
      expect(application.current_buffer.modified?).to be(true)
    end
  end

  it "exits its event loop on routed C-x C-c and closes the frontend" do
    events = %w[C-x C-c].map { |key| Roded::Event.new(:key, { key: key }) }
    scripted_frontend = ScriptedFrontend.new(events)
    app = described_class.new
    app.add_frontend(scripted_frontend)

    Timeout.timeout(2) { app.run }

    expect(scripted_frontend.closed).to be(true)
  end

  it "sets the core stop state without waiting for a frontend acknowledgement" do
    app = described_class.new
    app.instance_variable_set(:@frontends, [frontend])

    app.handle_event(Roded::Event.new(:key, { key: "C-x" }))
    app.handle_event(Roded::Event.new(:key, { key: "C-c" }))

    expect(app.instance_variable_get(:@stop_requested)).to be(true)
  end

  it "exits its event loop when M-x quit is submitted" do
    events = %w[Esc x q u i t Enter].map { |key| Roded::Event.new(:key, { key: key }) }
    scripted_frontend = ScriptedFrontend.new(events)
    app = described_class.new
    app.add_frontend(scripted_frontend)

    Timeout.timeout(2) { app.run }

    expect(scripted_frontend.closed).to be(true)
  end

  it "exits on a signal even while the minibuffer has focus" do
    scripted_frontend = ScriptedFrontend.new
    app = described_class.new
    app.add_frontend(scripted_frontend)
    app.start_minibuffer(:command, "M-x ")
    previous_term_handler = Signal.trap("TERM", "DEFAULT")
    Signal.trap("TERM", previous_term_handler)
    signal_thread = Thread.new do
      sleep 0.02
      Process.kill("TERM", Process.pid)
    end

    Timeout.timeout(2) { app.run }
    signal_thread.join
    restored_term_handler = Signal.trap("TERM", "IGNORE")
    Signal.trap("TERM", restored_term_handler)

    expect(scripted_frontend.closed).to be(true)
    expect(restored_term_handler).to eq(previous_term_handler)
  ensure
    Signal.trap("TERM", previous_term_handler) if previous_term_handler
  end

  it "shuts down when the frontend reaches end of input" do
    frontend = EndOfInputFrontend.new
    app = described_class.new
    app.add_frontend(frontend)

    Timeout.timeout(2) { app.run }

    expect(frontend.closed).to be(true)
  end

  it "reports file read and write errors without raising" do
    application.open_file("/no/such/roded/file")
    expect(frontend.messages.last).to match(/File not found/)

    buffer = Roded::Buffer.new("unsaved")
    buffer.insert_char("x")
    application.add_buffer(buffer)
    application.save_file("/no/such/roded/file")
    expect(frontend.messages.last).to match(/Error saving file/)
    expect(buffer.to_s).to eq("x")
    expect(buffer.modified?).to be(true)
  end

  it "closes the frontend after a command raises in the event loop" do
    events = [Roded::Event.new(:key, { key: "a" }), Roded::Event.new(:quit, {})]
    scripted_frontend = ScriptedFrontend.new(events)
    app = described_class.new
    app.add_frontend(scripted_frontend)
    app.define_singleton_method(:handle_event) { |_event| raise "command failure" }

    expect { Timeout.timeout(2) { app.run } }.to raise_error("command failure")
    expect(scripted_frontend.closed).to be(true)
  end

  it "saves the current buffer to disk" do
    Tempfile.create("roded-save") do |file|
      buffer = Roded::Buffer.new(file.path)
      buffer.lines = %w[saved content]
      buffer.filename = file.path
      application.add_buffer(buffer)

      application.save_file(file.path)

      expect(File.read(file.path)).to eq("saved\ncontent")
      expect(buffer.modified?).to be(false)
      expect(frontend.messages.last).to eq("File '#{file.path}' saved.")
    end
  end

  it "asks before save-as replaces an existing file" do
    Tempfile.create("roded-save-as-source") do |source|
      Tempfile.create("roded-save-as-target") do |target|
        source.write("source")
        source.flush
        target.write("target")
        target.flush
        application.open_file(source.path)
        application.current_buffer.insert_char("x")

        application.save_file(target.path)

        expect(application.focus).to eq(:minibuffer)
        expect(File.binread(target.path)).to eq("target")
        answer_minibuffer(application, "no")
        expect(application.current_buffer.filename).to eq(source.path)
        expect(application.current_buffer.modified?).to be(true)
        expect(File.binread(target.path)).to eq("target")
      end
    end
  end

  it "overwrites a save-as target after explicit confirmation" do
    Tempfile.create("roded-save-as-confirm-source") do |source|
      Tempfile.create("roded-save-as-confirm-target") do |target|
        source.write("source")
        source.flush
        target.write("target")
        target.flush
        application.open_file(source.path)
        buffer = application.current_buffer
        buffer.insert_char("x")

        application.save_file(target.path)
        answer_minibuffer(application, "yes")

        expect(File.binread(target.path)).to eq("xsource")
        expect(buffer.filename).to eq(target.path)
        expect(buffer.modified?).to be(false)
      end
    end
  end

  it "checks for an external file appearing after an unsaved path was created" do
    Dir.mktmpdir("roded-appeared") do |directory|
      path = File.join(directory, "new.txt")
      application.open_file(path)
      buffer = application.current_buffer
      buffer.insert_char("editor")
      File.write(path, "external")

      application.save_file(path)

      expect(application.focus).to eq(:minibuffer)
      expect(File.binread(path)).to eq("external")
      answer_minibuffer(application, "no")
      expect(buffer.modified?).to be(true)
    end
  end

  it "moves the buffer cursor by a page in buffer focus" do
    buffer = Roded::Buffer.new("buffer")
    buffer.lines = %w[a b c d e f]
    buffer.cursor_pos = { row: 1, col: 0 }
    application.add_buffer(buffer)

    application.handle_event(Roded::Event.new(:page_down, {}))

    expect(application.current_buffer.cursor_pos).to eq({ row: 4, col: 0 })
    expect(frontend.commands.last).to eq(Roded::Command.new(:render, {}))
  end

  it "uses the page size of the input source that issued the command" do
    first = FakeFrontend.new(page_size: 2)
    second = FakeFrontend.new(page_size: 5)
    application.instance_variable_set(:@frontends, [first, second])
    application.instance_variable_set(:@frontend_sources, { first => :first, second => :second })
    buffer = Roded::Buffer.new("buffer")
    buffer.lines = (0..8).map(&:to_s)
    application.add_buffer(buffer)

    application.handle_event(Roded::Event.new(:page_down, { source_id: :second }))

    expect(buffer.cursor_row).to eq(5)
  end

  it "treats page up and page down in minibuffer as cursor-to-start/end" do
    application.start_minibuffer(:command, "M-x ")
    %w[a b c].each do |char|
      application.handle_event(Roded::Event.new(:insert_char, { char: char }))
    end

    application.handle_event(Roded::Event.new(:page_up, {}))
    expect(frontend.commands.last).to eq(
      Roded::Command.new(:minibuffer_render, { prompt: "M-x ", text: "abc", cursor: 0 })
    )

    application.handle_event(Roded::Event.new(:page_down, {}))
    expect(frontend.commands.last).to eq(
      Roded::Command.new(:minibuffer_render, { prompt: "M-x ", text: "abc", cursor: 3 })
    )
  end

  it "moves the buffer cursor up by a page and clamps at the top" do
    buffer = Roded::Buffer.new("buffer")
    buffer.lines = %w[a b c d e f]
    buffer.cursor_pos = { row: 2, col: 0 }
    application.add_buffer(buffer)

    application.handle_event(Roded::Event.new(:page_up, {}))

    expect(application.current_buffer.cursor_pos).to eq({ row: 0, col: 0 })
    expect(frontend.commands.last).to eq(Roded::Command.new(:render, {}))
  end

  def answer_minibuffer(editor, response)
    response.each_char { |character| editor.minibuffer.insert_char(character) }
    editor.submit_minibuffer
  end

  it "scrolls the active view without moving point and clamps to document bounds" do
    application.startup
    buffer = application.current_buffer
    buffer.lines = (0..9).map(&:to_s)
    point = { row: 2, col: 0 }
    application.current_window.point = point

    application.handle_event(Roded::Event.new(:key, { key: "M-n" }))
    expect(application.current_window.top_line).to eq(1)
    expect(application.current_window.point).to eq(point)

    application.handle_event(Roded::Event.new(:key, { key: "M-N" }))
    expect(application.current_window.top_line).to eq(4)
    application.handle_event(Roded::Event.new(:key, { key: "M-N" }))
    expect(application.current_window.top_line).to eq(7)
    application.handle_event(Roded::Event.new(:key, { key: "M-N" }))
    expect(application.current_window.top_line).to eq(7)
  end
end
# rubocop:enable Metrics/BlockLength
