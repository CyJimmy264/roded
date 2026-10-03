require "spec_helper"

module Qt
  {
    Key_Escape: 0x01000000,
    Key_Return: 0x01000004,
    Key_Enter: 0x01000005,
    Key_Backspace: 0x01000003,
    Key_Delete: 0x01000007,
    Key_Left: 0x01000012,
    Key_Up: 0x01000013,
    Key_Right: 0x01000014,
    Key_Down: 0x01000015,
    Key_Tab: 0x01000001,
    Key_Space: 0x20,
    Key_F7: 0x01000036,
    Key_A: 0x41,
    Key_Z: 0x5a,
    ControlModifier: 0x04000000,
    AltModifier: 0x08000000,
    ShiftModifier: 0x02000000,
    MetaModifier: 0x10000000
  }.each do |name, value|
    const_set(name, value) unless const_defined?(name, false)
  end
end

require_relative "../lib/roded/frontends/qt/key_translator"

RSpec.describe Roded::Frontends::QtKeyTranslator do
  subject(:translator) { described_class.new }

  it "translates control, alt, and super modifiers independently" do
    expect(translator.translate({ key: Qt::Key_A, modifiers: Qt::ControlModifier, text: "\u0001" })).to eq("C-a")
    key = { key: Qt::Key_A, modifiers: Qt::AltModifier, text: "a" }
    expect(translator.translate(key)).to eq("M-a")
    expect(translator.translate({ key: Qt::Key_A, modifiers: Qt::MetaModifier, text: "a" })).to eq("s-a")
  end

  it "preserves combined modifiers, punctuation, and shifted text" do
    payload = { key: ",".ord, modifiers: Qt::AltModifier | Qt::MetaModifier, text: "," }
    expect(translator.translate(payload)).to eq("M-s-,")
    expect(translator.translate({ key: Qt::Key_A, modifiers: Qt::ShiftModifier, text: "A" })).to eq("A")
    shifted_paste = { key: "V".ord, modifiers: Qt::ControlModifier | Qt::ShiftModifier, text: "" }
    expect(translator.translate(shifted_paste)).to eq("C-S-v")
  end

  it "uses key event aliases from generated Qt payloads" do
    expect(translator.translate({ a: Qt::Key_F7, b: 0, c: "" })).to eq("F7")
    expect(translator.translate({ key: Qt::Key_Space, modifiers: Qt::ControlModifier, text: "" })).to eq("C-SPC")
    expect(translator.translate({ key: Qt::Key_Tab, modifiers: Qt::ShiftModifier, text: "\t" })).to eq("S-Tab")
  end
end
