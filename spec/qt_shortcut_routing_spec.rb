require "qt"
require "roded"
require_relative "../lib/roded/frontends/qt/key_translator"

# rubocop:disable Metrics/BlockLength
RSpec.describe "Qt shortcut routing" do
  let(:translator) { Roded::Frontends::QtKeyTranslator.new }
  let(:router) { Roded::CommandRouter.new(Roded::Keymap.new(Roded::Keymap::DEFAULT)) }

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
end
# rubocop:enable Metrics/BlockLength
