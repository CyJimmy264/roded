require "qt"
require "spec_helper"
require_relative "../lib/roded/frontends/qt"

module QtFrontendCloseSpecHelpers
  def close_fixture_application
    events = []
    application = Object.new
    application.define_singleton_method(:push_event) { |event| events << event }
    [application, events]
  end

  def connect_close_events(view, application, close_guard, clipboard)
    router = Roded::Frontends::QtInputRouter.new(
      application,
      Roded::Frontends::QtKeyTranslator.new,
      clipboard,
      :qt
    )
    router.connect(view) { close_guard.mark_pending }
  end

  def close_fixture_frontend(view, application, frontend)
    clipboard = Roded::Frontends::QtClipboardBridge.new
    dispatcher = Roded::Frontends::QtUiDispatcher.new(view, application, clipboard)
    close_guard = Roded::Frontends::QtCloseGuard.new(dispatcher)
    frontend.instance_variable_set(:@application, application)
    frontend.instance_variable_set(:@view, view)
    frontend.instance_variable_set(:@ui_dispatcher, dispatcher)
    frontend.instance_variable_set(:@close_guard, close_guard)
    frontend.instance_variable_set(:@input_queue, Queue.new)
    connect_close_events(view, application, close_guard, clipboard)
    [frontend, dispatcher]
  end

  def frontend_close_fixture
    application, events = close_fixture_application
    view = Roded::Frontends::QtEditorWindow.new
    frontend = Roded::Frontends::Qt.allocate
    frontend, dispatcher = close_fixture_frontend(view, application, frontend)
    [frontend, view, dispatcher, events]
  end
end

RSpec.describe "Qt frontend native close" do
  include QtFrontendCloseSpecHelpers

  before(:context) { @qt_application = QApplication.new(0, ["roded-close-spec"]) }
  after(:context) { @qt_application.quit }

  it "reopens a real Qt window to handle a cancelled close request" do
    frontend, view, dispatcher, events = frontend_close_fixture
    view.show
    QApplication.process_events
    view.window.close

    expect(events.map(&:type)).to include(:close_request)
    expect(view.window.is_visible).to be(false)
    frontend.handle_command(Roded::Command.new(:minibuffer_render, { prompt: "Save? ", text: "" }))
    dispatcher.send(:drain)
    QApplication.process_events
    expect(view.window.is_visible).to be(true)

    frontend.handle_command(Roded::Command.new(:minibuffer_clear, {}))
    dispatcher.send(:drain)
    expect(view.window.is_visible).to be(true)
    view.close
  end
end
