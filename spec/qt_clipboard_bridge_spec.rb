require "qt"
require "spec_helper"
require_relative "../lib/roded/frontends/qt"

RSpec.configure do |config|
  config.before(:suite) { QApplication.new(0, ["roded-clipboard-spec"]) }
end

module QtClipboardSpecHelpers
  def input_router_with_events(clipboard)
    events = []
    application = Object.new
    application.define_singleton_method(:push_event) { |event| events << event }
    router = Roded::Frontends::QtInputRouter.new(
      application,
      Roded::Frontends::QtKeyTranslator.new,
      clipboard,
      :qt
    )
    [router, events]
  end

  def press_clipboard_shortcut(router, key)
    router.enqueue_key(
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
    router, events = input_router_with_events(clipboard)
    press_clipboard_shortcut(router, "C-S-v")

    expect(events.map(&:type)).to eq([:paste])
    expect(events.first.payload).to include(text: "from clipboard", source_id: :qt, window_id: 42)
  end

  it "routes desktop copy and cut shortcuts to the core region commands" do
    bridge = Roded::Frontends::QtClipboardBridge.new
    router, events = input_router_with_events(bridge)

    %w[C-S-c C-S-x].each { |key| press_clipboard_shortcut(router, key) }

    expect(events.map { |event| event.payload[:key] }).to eq(%w[M-w C-w])
    expect(events.map { |event| event.payload[:source_id] }).to eq(%i[qt qt])
  end
end

RSpec.describe Roded::Frontends::QtUiDispatcher do
  it "coalesces obsolete editor snapshots while preserving discrete UI actions" do
    first = { revision: 1 }.freeze
    latest = { revision: 2 }.freeze
    view = double(render_layout: nil, display_message: nil)
    clipboard = double(write_text: nil)
    dispatcher = described_class.new(view, Object.new, clipboard)

    dispatcher.post(:layout, first)
    dispatcher.post(:message, "saved")
    dispatcher.post(:clipboard_write, "copied")
    dispatcher.post(:layout, latest)
    dispatcher.send(:drain)

    expect(view).to have_received(:render_layout).once.with(latest)
    expect(view).to have_received(:display_message).once.with("saved")
    expect(clipboard).to have_received(:write_text).once.with("copied")
  end
end

RSpec.describe Roded::Frontends::QtUiDispatcher, "coalesced echo state" do
  it "keeps only the latest pending picker and minibuffer states" do
    view = double(render_picker: nil, render_minibuffer: nil, clear_minibuffer: nil)
    dispatcher = described_class.new(view, Object.new, Object.new)

    dispatcher.post(:picker, { query: "old" })
    dispatcher.post(:minibuffer, { text: "draft" })
    dispatcher.post(:picker, { query: "new" })
    dispatcher.post(:minibuffer_clear)
    dispatcher.send(:drain)

    expect(view).to have_received(:render_picker).once.with(query: "new")
    expect(view).not_to have_received(:render_minibuffer)
    expect(view).to have_received(:clear_minibuffer).once
  end
end

RSpec.describe Roded::Frontends::QtUiDispatcher, "render queue bounds" do
  it "bounds repeated render publications to the newest editor snapshot" do
    dispatcher = described_class.new(Object.new, Object.new, Object.new)
    500.times { |revision| dispatcher.post(:layout, { revision: }.freeze) }

    pending = dispatcher.instance_variable_get(:@queue)

    expect(pending).to eq([[:layout, { revision: 499 }]])
  end
end
