require "qt"
require "spec_helper"
require_relative "../lib/roded/frontends/qt"

RSpec.describe "Qt frontend native close" do
  before(:context) { @qt_application = QApplication.new(0, ["roded-close-spec"]) }
  after(:context) { @qt_application.quit }

  it "rejects a native close while the core decides whether to quit" do
    events = []
    application = Object.new
    application.define_singleton_method(:push_event) { |event| events << event }
    view = Roded::Frontends::QtEditorWindow.new
    router = Roded::Frontends::QtInputRouter.new(
      application,
      Roded::Frontends::QtKeyTranslator.new,
      Roded::Frontends::QtClipboardBridge.new,
      :qt
    )
    router.connect(view)
    view.show
    QApplication.process_events

    closed = view.window.close
    QApplication.process_events

    expect(closed).to be(false)
    expect(events.map(&:type)).to include(:close_request)
    expect(view.window.is_visible).to be(true)
    view.close
  end
end
