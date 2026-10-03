require "qt"
require "roded"
require_relative "../lib/roded/frontends/qt/key_translator"
require_relative "../lib/roded/frontends/qt/input_router"
require_relative "../lib/roded/frontends/qt/clipboard_bridge"

# rubocop:disable Metrics/BlockLength
RSpec.describe "Qt shortcut routing" do
  let(:translator) { Roded::Frontends::QtKeyTranslator.new }
  let(:router) { Roded::CommandRouter.new(Roded::Keymap.new(Roded::Keymap::DEFAULT)) }

  before(:context) do
    @qt_application = QApplication.new(0, ["roded-shortcut-spec"]) unless QApplication.instance_exists
  end

  it "routes actual Qt modifier payloads for the supported Super aliases" do
    aliases = [
      [{ key: Qt::Key_J, modifiers: Qt::AltModifier | Qt::MetaModifier, text: "j" }, :save_buffer],
      [{ key: Qt::Key_K, modifiers: Qt::AltModifier | Qt::MetaModifier, text: "k" }, :kill_buffer],
      [{ key: Qt::Key_C, modifiers: Qt::AltModifier | Qt::MetaModifier, text: "c" }, :delete_window],
      [{ key: Qt::Key_W, modifiers: Qt::MetaModifier, text: "w" }, :other_window],
      [{ key: Qt::Key_Left, modifiers: Qt::MetaModifier, text: "" }, :shrink_window_horizontally],
      [{ key: Qt::Key_Right, modifiers: Qt::MetaModifier, text: "" }, :enlarge_window_horizontally],
      [{ key: Qt::Key_Comma, modifiers: Qt::MetaModifier, text: "," }, :previous_buffer],
      [{ key: Qt::Key_Period, modifiers: Qt::MetaModifier, text: "." }, :next_buffer]
    ]

    aliases.each do |payload, expected_type|
      key = translator.translate(payload)

      expect(router.route(key)).to eq(Roded::Event.new(expected_type, {}))
    end
  end

  it "keeps Alt and Super distinct and preserves Ctrl+Shift punctuation" do
    alt = translator.translate(key: Qt::Key_J, modifiers: Qt::AltModifier, text: "j")
    super_key = translator.translate(key: Qt::Key_J, modifiers: Qt::MetaModifier, text: "j")
    combined = translator.translate(
      key: Qt::Key_Less,
      modifiers: Qt::ControlModifier | Qt::ShiftModifier,
      text: "<"
    )

    expect([alt, super_key, combined]).to eq(["M-j", "s-j", "C-<"])
    expect(router.route(combined)).to eq(Roded::Event.new(:previous_buffer, {}))
  end

  it "routes Qt Menu and Alt+Menu to the project and buffer pickers" do
    menu = translator.translate(key: Qt::Key_Menu, modifiers: 0, text: "")
    alt_menu = translator.translate(key: Qt::Key_Menu, modifiers: Qt::AltModifier, text: "")

    expect(router.route(menu)).to eq(Roded::Event.new(:project_files, {}))
    expect(router.route(alt_menu)).to eq(Roded::Event.new(:switch_buffer, {}))
  end

  it "routes Qt Ctrl+@ to the same mark command as Ctrl+Space" do
    ctrl_at = translator.translate(
      key: Qt::Key_At,
      modifiers: Qt::ControlModifier | Qt::ShiftModifier,
      text: "@"
    )

    expect(ctrl_at).to eq("C-@")
    expect(router.route(ctrl_at)).to eq(Roded::Event.new(:set_mark, {}))
  end

  it "applies an Alt+Super key payload through Qt input routing into the core" do
    application = Roded::Application.new
    application.startup
    frontend_router = Roded::Frontends::QtInputRouter.new(
      application,
      translator,
      Roded::Frontends::QtClipboardBridge.new,
      :qt
    )
    payload = {
      key: Qt::Key_B,
      modifiers: Qt::AltModifier | Qt::MetaModifier,
      text: "b",
      window_id: application.current_window.object_id
    }

    frontend_router.enqueue_key(payload)
    application.handle_event(application.instance_variable_get(:@event_queue).pop)

    expect(application.current_buffer.to_s).to eq("\nbinding.irb")
  end
end
# rubocop:enable Metrics/BlockLength
