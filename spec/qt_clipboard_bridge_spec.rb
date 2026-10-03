require "qt"
require "spec_helper"
require_relative "../lib/roded/frontends/qt"

RSpec.configure do |config|
  config.before(:suite) { QApplication.new(0, ["roded-clipboard-spec"]) }
end

module QtClipboardSpecHelpers
  def frontend_with_events(clipboard)
    events = []
    application = Object.new
    application.define_singleton_method(:push_event) { |event| events << event }
    frontend = Roded::Frontends::Qt.allocate
    frontend.instance_variable_set(:@application, application)
    frontend.instance_variable_set(:@key_translator, Roded::Frontends::QtKeyTranslator.new)
    frontend.instance_variable_set(:@clipboard, clipboard)
    [frontend, events]
  end

  def press_clipboard_shortcut(frontend, key)
    frontend.send(
      :enqueue_key,
      {
        key: key[-1].upcase.ord,
        modifiers: Qt::ControlModifier | Qt::ShiftModifier,
        text: "",
        window_id: 42
      }
    )
  end
end

RSpec.describe Roded::Frontends::QtClipboardBridge do
  include QtClipboardSpecHelpers

  it "round trips UTF-8 multiline text through Qt's system clipboard" do
    clipboard = described_class.new
    clipboard.write_text("alpha\nвторой 🙂")

    expect(clipboard.read_text).to eq("alpha\nвторой 🙂")
  end

  it "writes core clipboard updates through the GUI dispatcher action" do
    clipboard = described_class.new
    dispatcher = Roded::Frontends::QtUiDispatcher.new(Object.new, Object.new, clipboard)

    dispatcher.send(:apply, :clipboard_write, "core selection")

    expect(clipboard.read_text).to eq("core selection")
  end
end

RSpec.describe "Qt clipboard key routing" do
  include QtClipboardSpecHelpers

  it "routes the paste shortcut through a core paste event" do
    clipboard = Roded::Frontends::QtClipboardBridge.new
    clipboard.write_text("from clipboard")
    frontend, events = frontend_with_events(clipboard)
    press_clipboard_shortcut(frontend, "C-S-v")

    expect(events.map(&:type)).to eq([:paste])
    expect(events.first.payload).to include(text: "from clipboard", source_id: :qt, window_id: 42)
  end

  it "routes desktop copy and cut shortcuts to the core region commands" do
    bridge = Roded::Frontends::QtClipboardBridge.new
    frontend, events = frontend_with_events(bridge)

    %w[C-S-c C-S-x].each { |key| press_clipboard_shortcut(frontend, key) }

    expect(events.map { |event| event.payload[:key] }).to eq(%w[M-w C-w])
    expect(events.map { |event| event.payload[:source_id] }).to eq(%i[qt qt])
  end
end
