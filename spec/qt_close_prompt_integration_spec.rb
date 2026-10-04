require "qt"
require "spec_helper"
require "tmpdir"
require_relative "../lib/roded/frontends/qt"

module QtClosePromptIntegrationSpecSupport
  ClosePromptSession = Struct.new(:application, :frontend, :buffer, :path, keyword_init: true)

  def run_close_prompt_choice(directory, choice, expected, frontends)
    path = File.join(directory, "#{choice}.txt")
    File.write(path, "original\n")
    session = build_close_prompt_session(path)
    frontends << session.frontend
    request_native_close(session)
    submit_close_prompt_choice(session, choice)
    expect_close_result(session, choice, expected)
  end

  def build_close_prompt_session(path)
    application = build_close_prompt_application(path)
    frontend = build_close_prompt_frontend(application)
    ClosePromptSession.new(application:, frontend:, buffer: application.current_buffer, path:)
  end

  def build_close_prompt_application(path)
    application = Roded::Application.new
    application.startup
    application.open_file(path)
    application.current_buffer.insert_char("X", at: application.current_window.point)
    application
  end

  def build_close_prompt_frontend(application)
    frontend = Roded::Frontends::Qt.new(application)
    application.add_frontend(frontend)
    dispatcher(frontend).send(:drain)
    frontend.view.show
    QApplication.process_events
    frontend
  end

  def request_native_close(session)
    drain_core_events(session.application)
    send_native_close_request(session)
    dispatcher(session.frontend).send(:drain)
    expect(close_prompt_text(session.frontend)).to include("Unsaved changes")
  end

  def send_native_close_request(session)
    expect(session.frontend.view.window.close).to be(false)
    QApplication.process_events
    handle_next_core_event(session.application)
  end

  def submit_close_prompt_choice(session, choice)
    key_code = { "s" => Qt::Key_S, "d" => Qt::Key_D, "c" => Qt::Key_C }.fetch(choice)
    deliver_close_prompt_key(session.application, session.frontend, key_code, choice)
    deliver_close_prompt_key(session.application, session.frontend, Qt::Key_Return, "\r")
    dispatcher(session.frontend).send(:drain) if choice == "c"
  end

  def expect_close_result(session, choice, expected)
    expect_file_contents(session.path, expected)
    expect_close_state(session, choice)
    expect(session.frontend.view.window.is_visible).to be(true) if choice == "c"
  end

  def expect_file_contents(path, expected)
    expect(File.binread(path)).to eq(expected)
  end

  def expect_close_state(session, choice)
    expect(session.buffer.modified?).to eq(choice != "s"), "close response was #{choice.inspect}"
    stopped = session.application.instance_variable_get(:@stop_requested)
    expect(stopped).to eq(choice != "c"), "close response was #{choice.inspect}"
  end

  def close_prompt_text(frontend)
    frontend.view.instance_variable_get(:@echo_area).widget.text
  end

  def deliver_close_prompt_key(application, frontend, key, text)
    payload = { key:, modifiers: 0, text:, window_id: application.current_window.object_id }
    frontend.instance_variable_get(:@input_router).enqueue_key(payload)
    application.handle_event(application.instance_variable_get(:@event_queue).pop)
  end

  def drain_core_events(application)
    queue = application.instance_variable_get(:@event_queue)
    application.handle_event(queue.pop) until queue.empty?
  end

  def handle_next_core_event(application)
    application.handle_event(application.instance_variable_get(:@event_queue).pop)
  end

  def dispatcher(frontend)
    frontend.instance_variable_get(:@ui_dispatcher)
  end
end

RSpec.describe "Qt close prompt integration" do
  include QtClosePromptIntegrationSpecSupport

  before(:context) do
    @qt_application = QApplication.new(0, ["roded-close-prompt-spec"])
  end

  after(:context) { @qt_application.quit }

  it "routes a native QWidget close through save, discard, and cancel decisions" do
    frontends = []
    cases = { "s" => "Xoriginal\n", "d" => "original\n", "c" => "original\n" }
    Dir.mktmpdir("roded-qt-close") do |directory|
      cases.each { |choice, expected| run_close_prompt_choice(directory, choice, expected, frontends) }
    end
  ensure
    frontends.each do |frontend|
      dispatcher(frontend).stop
      frontend.view.close
    end
  end
end
