require "spec_helper"

# rubocop:disable Metrics/BlockLength
RSpec.describe Roded::Application, "text commands" do
  subject(:application) { described_class.new }

  before { application.startup }

  it "selects the current line using the window point" do
    application.current_buffer.load_text("first line\nsecond")
    application.current_window.point = { row: 1, col: 2 }

    application.execute_command("select-current-line")

    expect(application.current_window.mark).to eq(row: 1, col: 0)
    expect(application.current_window.point).to eq(row: 1, col: 6)
  end

  it "tabifies selected indentation as one undoable transformation" do
    application.current_buffer.load_text("  first  value\n    second\n  third")
    application.current_window.mark = { row: 0, col: 0 }
    application.current_window.point = { row: 1, col: 8 }

    application.execute_command("tabify")

    expect(application.current_buffer.to_s).to eq("\tfirst\tvalue\n\t\tsecond\n  third")
    expect(application.undo).to be(true)
    expect(application.current_buffer.to_s).to eq("  first  value\n    second\n  third")
    expect(application.redo).to be(true)
    expect(application.current_buffer.to_s).to eq("\tfirst\tvalue\n\t\tsecond\n  third")
  end

  it "untabifies indentation across the whole buffer when no region is active" do
    application.current_buffer.load_text("\tfirst\n \tsecond\ninline\tvalue")

    application.execute_command("untabify")

    expect(application.current_buffer.to_s).to eq("  first\n   second\ninline  value")
    expect(application.undo).to be(true)
    expect(application.current_buffer.to_s).to eq("\tfirst\n \tsecond\ninline\tvalue")
    expect(application.redo).to be(true)
    expect(application.current_buffer.to_s).to eq("  first\n   second\ninline  value")
  end

  it "inserts local date and time formats through registered commands" do
    allow(Time).to receive(:now).and_return(Time.local(2026, 10, 3, 12, 34, 56))

    application.execute_command("insert-current-date-time")
    application.current_buffer.insert_char(" ", at: application.current_window.point)
    application.execute_command("insert-current-time")

    expect(application.current_buffer.to_s).to eq("03/10/2026 12:34:56 12:34:56")
  end

  it "inserts binding.irb on the following line with the current indentation" do
    application.current_buffer.load_text("  run_task")
    application.current_window.point = { row: 0, col: 4 }

    application.execute_command("insert-binding-irb")

    expect(application.current_buffer.to_s).to eq("  run_task\n  binding.irb")
    expect(application.undo).to be(true)
    expect(application.current_buffer.to_s).to eq("  run_task")
    expect(application.redo).to be(true)
    expect(application.current_buffer.to_s).to eq("  run_task\n  binding.irb")
  end

  it "does not edit readonly buffers from text commands" do
    application.current_buffer.load_text("\tprotected")
    application.current_buffer.readonly = true

    application.execute_command("untabify")
    application.execute_command("insert-current-time")

    expect(application.current_buffer.to_s).to eq("\tprotected")
    expect(application.current_buffer.modified?).to be(false)
  end

  it "routes the documented leader and Super text commands to registered actions" do
    names = {
      "C-c d d" => "insert-current-date-time",
      "C-c d t" => "insert-current-time",
      "C-c l" => "select-current-line",
      "C-c r b" => "insert-binding-irb",
      "M-s-b" => "insert-binding-irb",
      "M-s-d" => "insert-current-date-time",
      "M-s-t" => "insert-current-time",
      "M-s-u" => "untabify",
      "M-s-Tab" => "tabify",
      "s-l" => "select-current-line"
    }

    names.each do |key, command|
      routed = key.split.map { |chord| application.instance_variable_get(:@command_router).route(chord) }.last
      expect(routed).to eq(Roded::EditorCommand.new(:custom_command, { name: command }, nil, nil))
      expect(application.command_names).to include(command)
    end
  end
end
# rubocop:enable Metrics/BlockLength
