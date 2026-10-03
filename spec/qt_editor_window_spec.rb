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
    expect(editor.property("contextMenuPolicy")).to eq("NoContextMenu")
    expect(editor.to_plain_text).to eq("a<b\nc")
    expect(editor.to_html).to include("#3e4451")
    expect(editor.to_html).to include("&lt;b")
  end
end

RSpec.describe Roded::Frontends::QtEditorWindow, "Unicode syntax rendering" do
  include_context "Qt editor window lifecycle"

  it "renders a highlighted number after a wide Unicode grapheme" do
    view = described_class.new
    @views << view
    view.render_layout(
      tree: { window_id: 101 }, active_window_id: 101,
      windows: [{
        id: 101, text: "x = \"🙂\"; 42", point: { row: 0, col: 11 },
        name: "unicode.rb", mode: :ruby, active: true,
        tokens: [[{ start: 9, finish: 11, category: :number }]]
      }]
    )

    expect(view.editor.to_plain_text).to eq("x = \"🙂\"; 42")
    expect(view.editor.to_html).to include("#d19a66")
  end
end

RSpec.describe Roded::Frontends::QtEditorWindow, "search rendering" do
  include_context "Qt editor window lifecycle"

  it "renders search ranges with a distinct background color" do
    view = described_class.new
    @views << view
    view.render_layout(
      tree: { window_id: 101 }, active_window_id: 101,
      windows: [{
        id: 101, text: "needle row", point: { row: 0, col: 0 },
        highlight: { start: { row: 0, col: 0 }, finish: { row: 0, col: 6 } },
        name: "doc", active: true
      }]
    )

    expect(view.editor.to_html).to include("#e5c07b")
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

  it "places the core caret at exact character boundaries inside graphemes" do
    clipboard = Roded::Frontends::QtClipboardBridge.new
    cases = [
      ["a🙂b", 2, "b"],
      ["e\u0301x", 1, "\u0301"],
      ["e\u0301x", 2, "x"],
      ["👨‍👩‍👧‍👦x", 1, "‍👩‍👧‍👦"],
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

RSpec.describe Roded::Frontends::QtEditorWindow, "horizontal scrolling" do
  include_context "Qt editor window lifecycle"

  it "keeps long lines unwrapped and scrolls the Qt text viewport" do
    view = described_class.new
    @views << view
    view.render_layout(
      tree: { window_id: 101 }, active_window_id: 101,
      windows: [{ id: 101, text: "x" * 300, point: { row: 0, col: 299 }, name: "long", active: true }]
    )
    view.show
    view.window.resize(320, 180)
    QApplication.process_events

    expect(view.editor.to_plain_text).to eq("x" * 300)
    expect(view.editor.horizontal_scroll_bar.maximum).to be > 0
    expect(view.editor.horizontal_scroll_bar.value).to be > 0
  end
end

RSpec.describe Roded::Frontends::QtEditorWindow, "vertical scrolling" do
  include_context "Qt editor window lifecycle"

  it "restores the core top line in the real Qt vertical scrollbar" do
    view = described_class.new
    @views << view
    view.show
    lines = (1..100).map { |number| "line #{number}" }.join("\n")
    view.render_layout(
      tree: { window_id: 101 }, active_window_id: 101,
      windows: [{
        id: 101, text: lines, point: { row: 0, col: 0 }, top_line: 30,
        name: "long", active: true
      }]
    )
    QApplication.process_events

    scroll_bar = view.editor.vertical_scroll_bar
    expect(scroll_bar.value).to eq(30 * scroll_bar.single_step)
  end
end

RSpec.describe Roded::Frontends::QtEditorWindow, "tab display" do
  include_context "Qt editor window lifecycle"

  it "renders tabs with two-cell stops while keeping the caret at core columns" do
    view = described_class.new
    render_qt_snapshot(view, "界\t\tb", 3)

    expect(view.editor.to_plain_text).to eq("界    b")
    clipboard = Roded::Frontends::QtClipboardBridge.new
    clipboard.write_text("sentinel")
    view.editor.move_cursor(Roded::Frontends::QtCursorMapper::MOVE_RIGHT, 1)
    view.editor.copy

    expect(clipboard.read_text).to eq("b")
  end
end

RSpec.describe Roded::Frontends::QtEditorWindow, "visible caret" do
  include_context "Qt editor window lifecycle"

  it "marks the core point with a high-contrast underline" do
    view = described_class.new
    render_qt_snapshot(view, "abc", 1)
    view.show
    QApplication.process_events

    expect(view.editor.to_html).to include("#61afef")
    expect(view.editor.to_html).to include("text-decoration: underline")
    expect(view.editor.q_inspect[:properties][:cursorWidth]).to eq(2)
    expect(view.editor.height).to be > 0
    modeline = view.instance_variable_get(:@panes).fetch(101).instance_variable_get(:@modeline)
    expect(modeline.y).to be > view.editor.y
  end
end

RSpec.describe Roded::Frontends::QtEditorWindow, "split resizing" do
  include_context "Qt editor window lifecycle"

  it "applies the core split ratio to the real Qt splitter" do
    view = described_class.new
    @views << view
    view.show
    view.window.resize(960, 480)
    windows = [101, 202].map do |id|
      { id:, text: "pane #{id}", point: { row: 0, col: 0 }, name: "#{id}.txt", active: id == 101 }
    end
    base = { direction: :vertical, first: { window_id: 101 }, second: { window_id: 202 } }
    view.render_layout(tree: base.merge(ratio: 0.5), active_window_id: 101, windows:)
    QApplication.process_events
    view.render_layout(tree: base.merge(ratio: 0.7), active_window_id: 101, windows:)
    QApplication.process_events

    widths = view.instance_variable_get(:@panes).values.map { |pane| pane.container.width }
    expect(widths.first.to_f / widths.sum).to be_within(0.05).of(0.7)

    view.window.resize(1060, 480)
    QApplication.process_events
    widths = view.instance_variable_get(:@panes).values.map { |pane| pane.container.width }
    expect(widths.first.to_f / widths.sum).to be_within(0.05).of(0.7)
  end
end
