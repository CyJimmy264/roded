# rubocop:disable Metrics/BlockLength
RSpec.describe Roded::Application, "indent command" do
  def press_tab(application)
    application.handle_event(Roded::Event.new(:key, { key: "Tab" }))
  end

  it "indents the current line by two spaces as one undoable edit" do
    application = described_class.new
    application.startup
    application.current_buffer.load_text("one\ntwo")
    application.current_window.point = { row: 1, col: 1 }

    press_tab(application)

    expect(application.current_buffer.to_s).to eq("one\n  two")
    expect(application.current_window.point).to eq(row: 1, col: 3)
    expect(application.undo).to be(true)
    expect(application.current_buffer.to_s).to eq("one\ntwo")
  end

  it "indents every selected line and keeps the selection positions aligned" do
    application = described_class.new
    application.startup
    application.current_buffer.load_text("one\ntwo\nthree")
    application.current_window.mark = { row: 0, col: 1 }
    application.current_window.point = { row: 1, col: 2 }

    press_tab(application)

    expect(application.current_buffer.to_s).to eq("  one\n  two\nthree")
    expect(application.current_window.mark).to eq(row: 0, col: 3)
    expect(application.current_window.point).to eq(row: 1, col: 4)
    expect(application.undo).to be(true)
    expect(application.current_buffer.to_s).to eq("one\ntwo\nthree")
  end

  it "does not change a readonly buffer" do
    application = described_class.new
    application.startup
    application.current_buffer.load_text("readonly")
    application.current_buffer.readonly = true

    press_tab(application)

    expect(application.current_buffer.to_s).to eq("readonly")
    expect(application.current_buffer.modified?).to be(false)
  end
end
# rubocop:enable Metrics/BlockLength
