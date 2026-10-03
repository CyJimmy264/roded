require "qt"
require_relative "../lib/roded/frontends/qt/editor_window"
require_relative "../lib/roded/frontends/qt/clipboard_bridge"

module QtEditorWindowSpecHelpers
  def render_qt_snapshot(view, text, character_column)
    @views << view
    window = { id: 101, text:, point: { row: 0, col: character_column }, name: "unicode", active: true }
    view.render_layout(tree: { window_id: 101 }, active_window_id: 101, windows: [window])
  end
end

RSpec.shared_context "Qt editor window lifecycle" do
  include QtEditorWindowSpecHelpers

  before(:context) do
    @qt_application = QApplication.new(0, ["roded-spec"])
    @views = []
  end

  after(:context) do
    @views.each(&:close)
    QApplication.process_events
    @qt_application.quit
  end
end

RSpec.describe Roded::Frontends::QtEditorWindow, "split layout" do
  include_context "Qt editor window lifecycle"

  it "renders multiple read-only widgets inside a real Qt splitter" do
    view = described_class.new
    @views << view
    view.render_layout(
      tree: {
        direction: :vertical,
        first: { window_id: 101 },
        second: { window_id: 202 }
      }.freeze,
      active_window_id: 202,
      windows: [
        { id: 101, text: "first", point: { row: 0, col: 0 }, name: "first.rb", active: false },
        { id: 202, text: "second", point: { row: 0, col: 2 }, name: "second.rb", active: true }
      ].map(&:freeze).freeze
    )

    expect(view.editor_area).to be_a(QSplitter)
    expect(view.editor_area.count).to eq(2)
    expect(view.instance_variable_get(:@panes).length).to eq(2)
    expect(view.editor).to equal(view.instance_variable_get(:@panes).fetch(202).editor)
  end
end

RSpec.describe Roded::Frontends::QtEditorWindow, "region rendering" do
  include_context "Qt editor window lifecycle"

  it "renders the core region as a Qt text selection" do
    view = described_class.new
    @views << view
    view.render_layout(
      tree: { window_id: 101 },
      active_window_id: 101,
      windows: [
        {
          id: 101, text: "a<b\nc", point: { row: 0, col: 3 }, mark: { row: 0, col: 1 },
          name: "doc", active: true
        }
      ]
    )

    editor = view.editor
    expect(editor).to be_a(QTextEdit)
    expect(editor.to_plain_text).to eq("a<b\nc")
    expect(editor.to_html).to include("#3e4451")
    expect(editor.to_html).to include("&lt;b")
  end
end

RSpec.describe Roded::Frontends::QtEditorWindow, "split cleanup" do
  include_context "Qt editor window lifecycle"

  it "collapses back to the remaining Qt pane after a window is deleted" do
    view = described_class.new
    @views << view
    pane = { id: 101, text: "remaining", point: { row: 0, col: 0 }, name: "doc", active: true }
    view.render_layout(
      tree: { direction: :horizontal, first: { window_id: 101 }, second: { window_id: 202 } },
      active_window_id: 101,
      windows: [pane, pane.merge(id: 202, text: "closed", active: false)]
    )
    view.render_layout(
      tree: { window_id: 101 },
      active_window_id: 101,
      windows: [pane]
    )

    expect(view.editor_area).not_to be_a(QSplitter)
    expect(view.instance_variable_get(:@panes).keys).to eq([101])
  end
end

RSpec.describe Roded::Frontends::QtEditorWindow, "Unicode caret" do
  include_context "Qt editor window lifecycle"

  it "places the core caret before the next Qt grapheme" do
    clipboard = Roded::Frontends::QtClipboardBridge.new
    cases = [
      ["a🙂b", 2, "b"],
      ["e\u0301x", 1, "e\u0301"],
      ["e\u0301x", 2, "x"],
      ["👨‍👩‍👧‍👦x", 7, "x"]
    ]

    cases.each do |text, character_column, expected_next_character|
      view = described_class.new
      render_qt_snapshot(view, text, character_column)
      clipboard.write_text("sentinel")
      view.editor.move_cursor(Roded::Frontends::QtCursorMapper::MOVE_RIGHT, 1)
      view.editor.copy

      expect(clipboard.read_text).to eq(expected_next_character)
    end
  end
end
