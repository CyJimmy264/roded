require "spec_helper"
require "qt"
require_relative "../lib/roded/frontends/qt"

RSpec.describe Roded::Frontends::QtCursorMapper do
  it "maps Qt UTF-16 positions back to core characters and rows" do
    cases = [
      ["a🙂b", 3, { row: 0, col: 2 }],
      ["e\u0301x", 1, { row: 0, col: 1 }],
      ["e\u0301x", 2, { row: 0, col: 2 }],
      ["a\nb", 2, { row: 1, col: 0 }],
      ["a\n\nb", 2, { row: 1, col: 0 }],
      ["a\n\nb", 4, { row: 2, col: 0 }],
      ["a\tb", 2, { row: 0, col: 2 }]
    ]

    cases.each do |text, offset, expected|
      expect(described_class.core_position(text, offset)).to eq(expected)
    end
  end

  it "maps an empty scratch buffer to its only valid core position" do
    expect(described_class.utf16_offset("", row: 0, col: 0)).to eq(0)
    expect(described_class.core_position("", 0)).to eq(row: 0, col: 0)
  end

  it "adds the rendered blank-line cell when mapping into Qt UTF-16 offsets" do
    expect(described_class.utf16_offset("a\n\nb", row: 2, col: 0)).to eq(4)
  end

  it "maps the empty row after a final newline" do
    expect(described_class.utf16_offset("a\n", row: 1, col: 0)).to eq(2)
  end
end

RSpec.describe "Qt QTextEdit mouse hit testing" do
  it "uses QTextEdit hit testing to locate a mouse caret" do
    application = QApplication.new(0, ["roded-mouse-spec"])
    editor = QTextEdit.new
    editor.set_plain_text("one\ntwo")
    editor.resize(320, 160)
    editor.show
    cursor = editor.text_cursor
    cursor.set_position(6)
    editor.set_text_cursor(cursor)
    QApplication.process_events
    rect = editor.cursor_rect
    position = Qt::QPoint.new
    position.set_x(rect.x + 1)
    position.set_y(rect.y + (rect.height / 2))

    point = Roded::Frontends::QtCursorMapper.position_at(editor, position.x, position.y, "one\ntwo")

    expect(point).to eq(row: 1, col: 2)
  ensure
    editor&.close
    application&.quit
  end
end

RSpec.describe "Qt mouse input routing" do
  it "sends press, drag and release points through core selection events" do
    events = []
    application = Object.new
    application.define_singleton_method(:push_event) { |event| events << event }
    router = Roded::Frontends::QtInputRouter.new(
      application,
      Roded::Frontends::QtKeyTranslator.new,
      Roded::Frontends::QtClipboardBridge.new,
      :qt
    )
    anchor = { row: 0, col: 1 }
    finish = { row: 0, col: 4 }

    [
      { mouse_action: :press, button: Qt::LeftButton, position: anchor, window_id: 7 },
      { mouse_action: :move, buttons: Qt::LeftButton, position: finish, window_id: 7 },
      { mouse_action: :release, button: Qt::LeftButton, position: finish, window_id: 7 }
    ].each { |payload| expect(router.enqueue_mouse(payload)).to eq(:consume) }

    expect(events.map(&:payload)).to eq(
      [
        { point: anchor, mark: nil, source_id: :qt, window_id: 7 },
        { point: finish, mark: anchor, source_id: :qt, window_id: 7 },
        { point: finish, mark: anchor, source_id: :qt, window_id: 7 }
      ]
    )
  end
end
