require "qt"
require "spec_helper"
require_relative "../lib/roded/frontends/qt"

module QtInputIntegrationSpecHelpers
  def build_qt_editor(lines)
    application = build_application(lines)
    frontend = attach_qt_frontend(application)
    frontend.instance_variable_get(:@ui_dispatcher).send(:drain)
    frontend.view.show
    QApplication.process_events
    [application, frontend]
  end

  def build_application(lines)
    application = Roded::Application.new
    application.startup
    application.current_buffer.insert_text(lines.join("\n"), at: application.current_window.point)
    application.current_window.point = { row: 0, col: 0 }
    application
  end

  def attach_qt_frontend(application)
    frontend = Roded::Frontends::Qt.new(application)
    application.add_frontend(frontend)
    frontend
  end

  def deliver_qt_payload(application, frontend, payload)
    frontend.instance_variable_get(:@input_router).enqueue_key(payload)
    drain_core_events(application, frontend)
  end

  def deliver_qt_wheel(application, frontend, delta)
    payload = { angle_delta_y: delta, pixel_delta_y: 0, window_id: application.current_window.object_id }
    frontend.instance_variable_get(:@input_router).enqueue_wheel(payload)
    drain_core_events(application, frontend)
  end

  def drain_core_events(application, frontend)
    event_queue = application.instance_variable_get(:@event_queue)
    application.handle_event(event_queue.pop) until event_queue.empty?
    frontend.instance_variable_get(:@ui_dispatcher).send(:drain)
    QApplication.process_events
  end
end

RSpec.shared_context "Qt input integration lifecycle" do
  before(:context) do
    @qt_application = QApplication.new(0, ["roded-input-integration-spec"])
    @frontends = []
  end

  after(:context) do
    @frontends.each do |frontend|
      frontend.instance_variable_get(:@ui_dispatcher).stop
      frontend.view.close
    end
    QApplication.process_events
    @qt_application.quit
  end
end

RSpec.describe "Qt snapshot feedback" do
  include_context "Qt input integration lifecycle"
  include QtInputIntegrationSpecHelpers

  it "updates a real editor widget without routing render feedback as input" do
    application, frontend = build_qt_editor(%w[before after])
    @frontends << frontend

    application.handle_event(Roded::Event.new(:insert_char, { char: "!" }))
    frontend.instance_variable_get(:@ui_dispatcher).send(:drain)
    QApplication.process_events

    expect(application.current_buffer.to_s).to eq("!before\nafter")
    expect(frontend.view.editor.to_plain_text).to eq("!before\nafter")
    expect(frontend.instance_variable_get(:@input_queue)).to be_empty
  end
end

RSpec.describe "Qt Ctrl+N and Ctrl+P through editor session" do
  include_context "Qt input integration lifecycle"
  include QtInputIntegrationSpecHelpers

  it "moves the active core point with real Qt Ctrl+N and Ctrl+P payloads" do
    application, frontend = build_qt_editor((1..12).map { |number| "line #{number}" })
    @frontends << frontend
    expect(application.current_buffer.instance_variable_get(:@observers)).not_to include(frontend)

    deliver_qt_payload(application, frontend, key: Qt::Key_N, modifiers: Qt::ControlModifier, text: "\u000e")
    expect(application.current_window.point).to eq(row: 1, col: 0)

    deliver_qt_payload(application, frontend, key: Qt::Key_P, modifiers: Qt::ControlModifier, text: "\u0010")
    expect(application.current_window.point).to eq(row: 0, col: 0)
  end
end

RSpec.describe "Qt Meta punctuation through editor session" do
  include_context "Qt input integration lifecycle"
  include QtInputIntegrationSpecHelpers

  it "moves to the document boundaries with real Qt Alt+Shift punctuation" do
    application, frontend = build_qt_editor((1..100).map { |number| "line #{number}" })
    @frontends << frontend

    deliver_qt_payload(
      application,
      frontend,
      key: Qt::Key_Comma, modifiers: Qt::AltModifier | Qt::ShiftModifier, text: "<"
    )
    expect(application.current_window.point).to eq(row: 0, col: 0)

    deliver_qt_payload(
      application,
      frontend,
      key: Qt::Key_Period, modifiers: Qt::AltModifier | Qt::ShiftModifier, text: ">"
    )
    expect(application.current_window.point).to eq(row: 99, col: 8)
  end
end

RSpec.describe "Qt space and final newline through editor session" do
  include_context "Qt input integration lifecycle"
  include QtInputIntegrationSpecHelpers

  it "inserts a real Space key event into the core buffer" do
    application, frontend = build_qt_editor([])
    @frontends << frontend

    deliver_qt_payload(application, frontend, key: Qt::Key_Space, modifiers: 0, text: " ")

    expect(application.current_buffer.to_s).to eq(" ")
  end

  it "moves Qt Meta+Shift+period to the editable row after a final newline" do
    application = Roded::Application.new
    application.startup
    application.current_buffer.load_text("alpha\n")
    frontend = attach_qt_frontend(application)
    @frontends << frontend
    frontend.instance_variable_get(:@ui_dispatcher).send(:drain)
    frontend.view.show
    QApplication.process_events

    deliver_qt_payload(
      application, frontend,
      key: Qt::Key_Period, modifiers: Qt::AltModifier | Qt::ShiftModifier, text: ">"
    )

    expect(application.current_window.point).to eq(row: 1, col: 0)
    expect(frontend.view.editor.text_cursor.position).to eq(6)
  end
end

RSpec.describe "Qt undo and redo through editor session" do
  include_context "Qt input integration lifecycle"
  include QtInputIntegrationSpecHelpers

  it "routes Ctrl+Slash undo and the redo sequence through the live editor" do
    application, frontend = build_qt_editor([])
    @frontends << frontend

    deliver_qt_payload(application, frontend, key: Qt::Key_X, modifiers: 0, text: "x")
    deliver_qt_payload(application, frontend, key: Qt::Key_Y, modifiers: 0, text: "y")
    expect(frontend.view.editor.to_plain_text).to eq("xy ")

    deliver_qt_payload(
      application, frontend,
      key: Qt::Key_Slash, modifiers: Qt::ControlModifier, text: "\u001f"
    )
    expect(application.current_buffer.to_s).to eq("")
    expect(frontend.view.editor.to_plain_text).to eq(" ")
    expect(frontend.view.editor.text_cursor.position).to eq(0)

    deliver_qt_payload(
      application, frontend, key: Qt::Key_C, modifiers: Qt::ControlModifier, text: "\u0003"
    )
    deliver_qt_payload(application, frontend, key: Qt::Key_R, modifiers: 0, text: "r")
    deliver_qt_payload(application, frontend, key: Qt::Key_D, modifiers: 0, text: "d")

    expect(application.current_buffer.to_s).to eq("xy")
    expect(frontend.view.editor.to_plain_text).to eq("xy ")
    expect(frontend.view.editor.text_cursor.position).to eq(2)
  end
end

RSpec.describe "Qt page geometry through editor session" do
  include_context "Qt input integration lifecycle"
  include QtInputIntegrationSpecHelpers

  it "captures the active pane page size on the GUI input path" do
    application, frontend = build_qt_editor((1..200).map { |number| "line #{number}" })
    @frontends << frontend
    window_id = application.current_window.object_id
    page_size = frontend.view.page_size(window_id)

    deliver_qt_payload(
      application, frontend,
      key: Qt::Key_V, modifiers: Qt::ControlModifier, text: "\u0016", window_id:
    )

    expect(page_size).to be > 1
    expect(application.current_window.point).to eq(row: page_size, col: 0)
  end
end

RSpec.describe "Qt wheel input through editor session" do
  include_context "Qt input integration lifecycle"
  include QtInputIntegrationSpecHelpers

  it "scrolls the core viewport and real Qt scrollbar from wheel input" do
    application, frontend = build_qt_editor((1..80).map { |number| "line #{number}" })
    @frontends << frontend
    deliver_qt_wheel(application, frontend, -120)

    expect(application.current_window.top_line).to eq(3)
    expect(application.current_window.point).to eq(row: 3, col: 0)
    scroll_bar = frontend.view.editor.vertical_scroll_bar
    expect(scroll_bar.value).to eq(3 * scroll_bar.single_step)
  end
end

RSpec.describe "Qt fractional wheel input through editor session" do
  include_context "Qt input integration lifecycle"
  include QtInputIntegrationSpecHelpers

  it "accumulates fractional wheel input before scrolling a line" do
    application, frontend = build_qt_editor((1..80).map { |number| "line #{number}" })
    @frontends << frontend
    deliver_qt_wheel(application, frontend, -60)
    expect(application.current_window.top_line).to eq(0)

    deliver_qt_wheel(application, frontend, -60)
    expect(application.current_window.top_line).to eq(3)
    scroll_bar = frontend.view.editor.vertical_scroll_bar
    expect(scroll_bar.value).to eq(3 * scroll_bar.single_step)
  end
end
