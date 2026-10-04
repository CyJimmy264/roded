require "timeout"

module BackgroundSyntaxRuntimeSpecSupport
  class Frontend < ScriptedFrontend
    attr_reader :updates

    def initialize(events)
      super
      @updates = Queue.new
    end

    def handle_command(command)
      @updates << command
      super
    end
  end

  def wait_for_colored_edit(frontend)
    Timeout.timeout(10) do
      loop do
        update = frontend.updates.pop
        next unless update.type == :render

        frame = update.payload[:editor_snapshot][:windows].first
        return frame if frame[:lines][750].include?("X") && !frame[:tokens][750].empty?
      end
    end
  end
end

RSpec.describe Roded::Application, "background syntax runtime" do
  include BackgroundSyntaxRuntimeSpecSupport

  it "applies child results through the real core loop and reaps the child on quit" do
    app = described_class.new
    app.startup
    app.current_buffer.major_mode = :ruby
    app.current_buffer.load_text(Array.new(1500, 'value = "🙂"; 42').join("\n"))
    app.current_window.point = { row: 750, col: 9 }
    frontend = BackgroundSyntaxRuntimeSpecSupport::Frontend.new([Roded::InputEvent.new(:insert_char, { char: "X" })])
    app.add_frontend(frontend)
    runtime = Thread.new { app.run(manage_signals: false) }
    frame = wait_for_colored_edit(frontend)
    expect(frame[:tokens]).to eq(Roded::SyntaxHighlighter.new.spans(:ruby, frame[:lines]))
    app.push_event(Roded::InputEvent.new(:quit, {}))
    expect(runtime.join(5)).to eq(runtime)
    expect(frontend.closed).to be(true)
    expect(app.instance_variable_get(:@ruby_highlight_worker).instance_variable_get(:@pid)).to be_nil
  ensure
    app&.push_event(Roded::InputEvent.new(:quit, {})) if runtime&.alive?
    runtime&.join(5)
    app&.shutdown_syntax_highlighting
  end
end
