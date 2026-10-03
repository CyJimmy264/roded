require "qt"
require "spec_helper"
require_relative "../lib/roded/frontends/qt"

RSpec.configure do |config|
  config.before(:suite) { QApplication.new(0, ["roded-clipboard-spec"]) }
end

RSpec.describe Roded::Frontends::QtClipboardBridge do
  it "round trips UTF-8 multiline text through Qt's system clipboard" do
    clipboard = described_class.new
    clipboard.write_text("alpha\nвторой 🙂")

    expect(clipboard.read_text).to eq("alpha\nвторой 🙂")
  end
end

RSpec.describe "Qt clipboard key routing" do
  it "routes the paste shortcut through a core paste event" do
    clipboard = Roded::Frontends::QtClipboardBridge.new
    clipboard.write_text("from clipboard")
    events = []
    application = Object.new
    application.define_singleton_method(:push_event) { |event| events << event }
    frontend = Roded::Frontends::Qt.allocate
    frontend.instance_variable_set(:@application, application)
    frontend.instance_variable_set(:@key_translator, Roded::Frontends::QtKeyTranslator.new)
    frontend.instance_variable_set(:@clipboard, clipboard)

    frontend.send(
      :enqueue_key,
      { key: "V".ord, modifiers: Qt::ControlModifier | Qt::ShiftModifier, text: "", window_id: 42 }
    )

    expect(events.map(&:type)).to eq([:paste])
    expect(events.first.payload).to include(text: "from clipboard", source_id: :qt, window_id: 42)
  end
end
