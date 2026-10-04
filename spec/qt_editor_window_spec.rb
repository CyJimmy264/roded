require "qt"
require_relative "../lib/roded/frontends/qt/editor_window"
require_relative "../lib/roded/frontends/qt/clipboard_bridge"

module QtEditorWindowSpecHelpers
  def margin_values(margins)
    %i[left top right bottom].map { |side| margins.public_send(side) }
  end

  def render_qt_snapshot(view, text, character_column)
    @views << view
    window = { id: 101, text:, point: { row: 0, col: character_column }, name: "unicode", active: true }
    view.render_layout(tree: { window_id: 101 }, active_window_id: 101, windows: [window])
  end

  def render_qt_split(view)
    view.render_layout(
      tree: {
        direction: :vertical, first: { window_id: 101 }, second: { window_id: 202 }
      },
      active_window_id: 101,
      windows: [101, 202].map do |id|
        { id:, text: "pane #{id}", point: { row: 0, col: 0 }, name: "#{id}.rb", active: id == 101 }
      end
    )
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

RSpec.describe Roded::Frontends::QtEditorWindow, "minibuffer height" do
  include_context "Qt editor window lifecycle"

  it "sizes the echo area to its lines and gives the remaining height to split panes" do
    view = described_class.new
    @views << view
    render_qt_split(view)
    view.show
    view.window.resize(960, 640)
    3.times { QApplication.process_events }

    echo = view.instance_variable_get(:@echo_area).widget
    content = view.instance_variable_get(:@content_host)
    line_height = echo.font_metrics.line_spacing
    expect(echo.height).to eq(line_height)
    expect(content.height).to be > view.window.height * 0.9

    view.render_picker(prompt: "M-x ", query: "", selected_index: 0, candidates: %w[undo redo quit])
    3.times { QApplication.process_events }
    picker_lines = echo.text.split("\n", -1).length
    expect(echo.height).to eq(line_height * picker_lines)
    expect(echo.height).to be > line_height
    expect(content.height + echo.height).to be_within(1).of(view.window.height)
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
    expect(editor).to be_a(Qt::QPlainTextEdit)
    expect(editor.property("contextMenuPolicy")).to eq("NoContextMenu")
    expect(editor.to_plain_text).to eq("a<b \nc")
    expect(editor.to_html).to include("#3e4451")
    expect(editor.to_html).to include("&lt;b</span>")
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

    expect(view.editor.to_plain_text).to eq("x = \"🙂\"; 42 ")
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

RSpec.describe Roded::Frontends::QtEditorWindow, "pane replacement" do
  include_context "Qt editor window lifecycle"

  it "remounts a replacement pane when the window tree shape is unchanged" do
    view = described_class.new
    @views << view
    snapshot = {
      tree: { window_id: 101 }, active_window_id: 101,
      windows: [{ id: 101, text: "old pane", point: { row: 0, col: 0 }, name: "doc", active: true }]
    }
    view.render_layout(snapshot)
    view.show
    QApplication.process_events
    old_root = view.editor_area
    replacement = Roded::Frontends::QtEditorPane.new(view.window)
    view.instance_variable_get(:@panes)[101] = replacement
    updated_snapshot = snapshot.merge(windows: [snapshot[:windows].first.merge(text: "new pane")])

    view.render_layout(updated_snapshot)
    QApplication.process_events

    expect(view.editor_area.equal?(replacement.container)).to be(true)
    expect(view.editor_area.is_visible).to be(true)
    expect(old_root.is_visible).to be(false)
    expect(view.editor.to_plain_text).to eq("new pane")
  end
end

RSpec.describe Roded::Frontends::QtEditorWindow, "reused pane visibility" do
  include_context "Qt editor window lifecycle"

  it "shows a pane again after it was returned to the pool" do
    view = described_class.new
    @views << view
    first = { id: 101, text: "first", point: { row: 0, col: 0 }, name: "first", active: true }
    second = first.merge(id: 202, text: "second", active: false)
    view.render_layout(
      tree: { direction: :horizontal, first: { window_id: 101 }, second: { window_id: 202 } },
      active_window_id: 101,
      windows: [first, second]
    )
    view.show
    QApplication.process_events
    view.render_layout(tree: { window_id: 101 }, active_window_id: 101, windows: [first])
    reused = first.merge(id: 303, text: "reused", active: false)
    view.render_layout(
      tree: { direction: :horizontal, first: { window_id: 101 }, second: { window_id: 303 } },
      active_window_id: 101,
      windows: [first, reused]
    )
    QApplication.process_events

    expect(view.instance_variable_get(:@panes).fetch(303).container.is_visible).to be(true)
    expect(view.instance_variable_get(:@panes).fetch(303).editor.to_plain_text).to eq("reused")
  end
end

RSpec.describe Roded::Frontends::QtEditorWindow, "Unicode caret" do
  include_context "Qt editor window lifecycle"

  it "places the core caret at exact character boundaries inside graphemes" do
    cases = [
      ["a🙂b", 2, 3],
      ["e\u0301x", 1, 1],
      ["e\u0301x", 2, 2],
      ["👨‍👩‍👧‍👦x", 1, 2],
      ["👨‍👩‍👧‍👦x", 7, 11]
    ]

    cases.each do |text, character_column, expected_utf16_position|
      view = described_class.new
      render_qt_snapshot(view, text, character_column)

      expect(view.editor.text_cursor.position).to eq(expected_utf16_position)
    end
  end
end

RSpec.describe Roded::Frontends::QtEditorWindow, "multi-line UTF-16 caret" do
  include_context "Qt editor window lifecycle"

  it "counts preceding lines when setting a UTF-16 document offset" do
    view = described_class.new
    @views << view
    view.render_layout(
      tree: { window_id: 101 }, active_window_id: 101,
      windows: [{
        id: 101, text: "🙂\nsecond", point: { row: 1, col: 2 }, name: "unicode", active: true
      }]
    )

    expect(view.editor.to_plain_text).to eq("🙂\nsecond")
    expect(view.editor.text_cursor.position).to eq(5)
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

RSpec.describe Roded::Frontends::QtEditorWindow, "tab display width" do
  include_context "Qt editor window lifecycle"

  it "expands tabs to two-cell display stops in the real Qt text widget" do
    view = described_class.new
    @views << view
    view.render_layout(
      tree: { window_id: 101 }, active_window_id: 101,
      windows: [{ id: 101, text: "a\tb\tc", point: { row: 0, col: 5 }, name: "tabs", active: true }]
    )
    view.show
    QApplication.process_events

    expect(view.editor.to_plain_text).to eq("a b c ")
  end
end

RSpec.describe Roded::Frontends::QtEditorWindow, "right-edge block caret" do # rubocop:disable Metrics/BlockLength
  include_context "Qt editor window lifecycle"

  it "reserves the full block and document margin when revealing an edge position" do
    view = described_class.new
    text = "x" * 300
    render_qt_snapshot(view, text, 0)
    view.show
    3.times { QApplication.process_events }
    editor = view.editor
    margin = editor.document.property("documentMargin").to_f
    threshold = editor.viewport.width - margin
    column = (0..text.length).bsearch do |candidate|
      Roded::Frontends::QtCursorMapper.line_horizontal_offset(editor, text, candidate) >= threshold
    end
    render_qt_snapshot(view, text, column)
    3.times { QApplication.process_events }

    width = editor.font_metrics.horizontal_advance("x", 1)
    expect(editor.cursor_rect.x + width + margin).to be <= editor.viewport.width
    expect(editor.horizontal_scroll_bar.value).to be > 0
  end

  it "keeps a whole expanded tab cell inside the viewport" do
    view = described_class.new
    text = "\t" * 150
    render_qt_snapshot(view, text, 60)
    view.show
    3.times { QApplication.process_events }
    editor = view.editor
    width = editor.font_metrics.horizontal_advance("  ", 2)
    margin = editor.document.property("documentMargin").to_f

    expect(editor.cursor_rect.x + width + margin).to be <= editor.viewport.width
    expect(editor.horizontal_scroll_bar.value).to be > 0
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
        id: 101, text: lines, point: { row: 30, col: 0 }, top_line: 30,
        name: "long", active: true
      }]
    )
    QApplication.process_events

    scroll_bar = view.editor.vertical_scroll_bar
    expect(scroll_bar.value).to eq(30 * scroll_bar.single_step)
  end
end

RSpec.describe Roded::Frontends::QtEditorWindow, "point visibility" do
  include_context "Qt editor window lifecycle"

  it "keeps a moved point visible when it leaves the current viewport" do
    view = described_class.new
    @views << view
    lines = (1..100).map { |number| "line #{number}" }.join("\n")
    view.render_layout(
      tree: { window_id: 101 }, active_window_id: 101,
      windows: [{ id: 101, text: lines, point: { row: 99, col: 8 }, top_line: 0, name: "long", active: true }]
    )
    view.show
    QApplication.process_events

    scroll_bar = view.editor.vertical_scroll_bar
    expect(scroll_bar.value).to be > 0
    expect(view.editor.to_plain_text).to include("line 100")
    modeline = view.instance_variable_get(:@panes).fetch(101).instance_variable_get(:@modeline)
    expect(modeline.text).to include("100:9")
  end
end

RSpec.describe Roded::Frontends::QtEditorWindow, "tab display" do
  include_context "Qt editor window lifecycle"

  it "renders tabs with two-cell stops while keeping the caret at core columns" do
    view = described_class.new
    render_qt_snapshot(view, "界\t\tb", 3)

    expect(view.editor.to_plain_text).to eq("界    b")
    expect(view.editor.text_cursor.position).to eq(5)
  end
end

RSpec.describe Roded::Frontends::QtEditorWindow, "visible caret" do
  include_context "Qt editor window lifecycle"

  it "shows an Emacs-like block cursor and active-line background" do
    view = described_class.new
    render_qt_snapshot(view, "abc", 1)
    view.show
    QApplication.process_events

    expect(view.editor.to_html).to include("#61afef")
    expect(view.editor.to_html).to include("background-color:#343a46")
    expect(view.editor.to_html).to include("background-color:#61afef")
    expect(view.editor.q_inspect[:properties][:cursorWidth]).to eq(2)
    expect(view.editor.height).to be > 0
    modeline = view.instance_variable_get(:@panes).fetch(101).instance_variable_get(:@modeline)
    expect(modeline.y).to be > view.editor.y
  end
end

RSpec.describe Roded::Frontends::QtEditorWindow, "startup focus" do
  include_context "Qt editor window lifecycle"

  it "gives keyboard focus to the active editor after the window is shown" do
    view = described_class.new
    render_qt_snapshot(view, "opened file", 0)
    view.show
    QApplication.process_events

    expect(view.window.focus_widget).to equal(view.editor)
  end

  it "restores keyboard focus after the window manager activates the window" do
    view = described_class.new
    render_qt_snapshot(view, "opened file", 0)
    view.show
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.2
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      QApplication.process_events
      sleep 0.01
    end

    expect(view.window.focus_widget).to equal(view.editor)
  end
end

RSpec.describe Roded::Frontends::QtEditorWindow, "empty scratch" do
  include_context "Qt editor window lifecycle"

  it "renders an empty scratch buffer without an invalid cursor range" do
    view = described_class.new
    render_qt_snapshot(view, "", 0)

    expect(view.editor.to_plain_text).to eq(" ")
    expect(view.editor.text_cursor.position).to eq(0)
    expect(view.editor.to_html).to include("background-color:#343a46")
    expect(view.editor.to_html).to include("background-color:#61afef")
  end
end

RSpec.describe Roded::Frontends::QtEditorWindow, "blank lines" do
  include_context "Qt editor window lifecycle"

  it "preserves blank lines and the final newline in the rendered document" do
    texts = {
      "internal blank line" => "a\n\nb",
      "trailing blank line" => "a\n\n",
      "only blank line" => "\n",
      "multiple blank lines and final newline" => "a\n\n\nb\n"
    }
    texts.each_value do |text|
      view = described_class.new
      render_qt_snapshot(view, text, 0)

      expected = text.split("\n", -1).map { |line| line.empty? ? " " : line }.join("\n")
      expect(view.editor.to_plain_text).to eq(expected), "expected Qt to preserve blank rows in #{text.inspect}"
    end
  end

  it "shows a block caret on the active blank line" do
    view = described_class.new
    view.render_layout(
      tree: { window_id: 101 }, active_window_id: 101,
      windows: [{ id: 101, text: "first\n\nthird", point: { row: 1, col: 0 }, name: "doc", active: true }]
    )

    expect(view.editor.to_html).to include("color:#282c34; background-color:#61afef;\"> </span>")
    expect(view.editor.text_cursor.position).to eq(6)
  end
end

RSpec.describe Roded::Frontends::QtEditorWindow, "final newline row" do
  include_context "Qt editor window lifecycle"

  it "places the caret on the empty row after a final newline" do
    view = described_class.new
    view.render_layout(
      tree: { window_id: 101 }, active_window_id: 101,
      windows: [{ id: 101, text: "a\n", point: { row: 1, col: 0 }, name: "doc", active: true }]
    )

    expect(view.editor.to_plain_text).to eq("a\n ")
    expect(view.editor.text_cursor.position).to eq(2)
  end

  it "shows the end-of-line caret in a cell after the text" do
    view = described_class.new
    view.render_layout(
      tree: { window_id: 101 }, active_window_id: 101,
      windows: [{ id: 101, text: "abc", point: { row: 0, col: 3 }, name: "doc", active: true }]
    )

    expect(view.editor.to_html).to include("background-color:#61afef")
    expect(view.editor.text_cursor.position).to eq(3)
    expect(view.editor.to_plain_text).to eq("abc ")
  end
end

RSpec.describe Roded::Frontends::QtEditorWindow, "visible editor layout" do
  include_context "Qt editor window lifecycle"

  it "sizes the editor and modeline to the visible window after garbage collection" do
    view = described_class.new
    @views << view
    render_qt_snapshot(view, "first\nsecond\nthird", 0)
    view.show
    GC.start
    QApplication.process_events

    pane = view.instance_variable_get(:@panes).fetch(101)
    modeline = pane.instance_variable_get(:@modeline)
    expect(pane.container.width).to be > 500
    expect(pane.container.height).to be > 300
    expect(view.window.is_visible).to be(true)
    expect(pane.container.is_visible).to be(true)
    expect(view.editor.is_visible).to be(true)
    expect(view.editor.width).to be > 500
    expect(view.editor.height).to be > 300
    expect(modeline.y).to be > view.editor.y
    expect(modeline.height).to be > 0
  end
end

RSpec.describe Roded::Frontends::QtEditorWindow, "zero-spacing editor widgets" do
  include_context "Qt editor window lifecycle"

  it "removes layout and widget margins around panes, modelines, and echo area" do
    view = described_class.new
    render_qt_snapshot(view, "text", 0)
    pane = view.instance_variable_get(:@panes).fetch(101)
    modeline = pane.instance_variable_get(:@modeline)

    expect(margin_values(pane.container.layout.contents_margins)).to eq([0, 0, 0, 0])
    expect(pane.container.layout.spacing).to eq(0)
    expect(margin_values(pane.container.contents_margins)).to eq([0, 0, 0, 0])
    expect(margin_values(view.editor.contents_margins)).to eq([0, 0, 0, 0])
    expect(margin_values(view.instance_variable_get(:@window_layout).contents_margins)).to eq([0, 0, 0, 0])
    expect(margin_values(view.instance_variable_get(:@content_layout).contents_margins)).to eq([0, 0, 0, 0])
    expect(view.instance_variable_get(:@window_layout).spacing).to eq(0)
    expect(view.instance_variable_get(:@content_layout).spacing).to eq(0)
    expect(modeline.object_name).to eq("rodedModeline")
    expect(modeline.margin).to eq(0)
    expect(view.instance_variable_get(:@echo_area).widget.margin).to eq(0)
    expect(view.window.style_sheet).to include("QLabel#rodedModeline { border-top: 1px solid #4b5263; }")
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
