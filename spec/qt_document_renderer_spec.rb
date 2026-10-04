require "spec_helper"
require "qt"
require_relative "../lib/roded/frontends/qt/editor_pane"

module QtDocumentRendererSpecSupport
  def snapshot(lines, point, **overlays)
    { text: lines.join("\n"), lines:, point:, mark: nil, highlight: nil,
      tokens: Roded::SyntaxHighlighter.new.spans(:ruby, lines) }.merge(overlays)
  end

  def expect_native_frame(state)
    @renderer.render(state, state[:text])
    expect_matching_content(state)
    expect_native_positions(state[:lines])
    expect(@editor.to_html.scan("background-color:#61afef").length).to eq(1)
    expect_current_line_background(state[:point][:row])
  end

  def expect_current_line_background(row)
    paragraphs = @editor.to_html.scan(/<(?:p|pre) [^>]*>/)
    active = paragraphs.each_index.select { |index| paragraphs[index].include?("background-color:#343a46") }
    expect(active).to eq([row])
  end

  def expect_matching_content(state)
    @reference.set_html(Roded::Frontends::QtEditorHtmlRenderer.new(state[:text], state).render)
    expect(@editor.to_plain_text).to eq(@reference.to_plain_text)
    expect(@editor.document.block_count).to eq(state[:lines].length)
  end

  def expect_native_positions(lines)
    lines.each_index do |row|
      cursor = @editor.text_cursor
      Roded::Frontends::QtCursorMapper.move_to_row(cursor, row)
      expect(@renderer.row_position(row)).to eq(cursor.position)
    end
  end
end

RSpec.shared_context "Qt native document rendering" do
  include QtDocumentRendererSpecSupport

  before(:context) { @qt_application = QApplication.new(0, ["roded-document-spec"]) }
  before do
    @editor = Roded::Frontends::QtTextEditor.new
    @reference = QTextEdit.new
    @editor.set_undo_redo_enabled(false)
    @renderer = Roded::Frontends::QtDocumentRenderer.new(@editor)
  end
  after do
    [@editor, @reference].each(&:close)
    QApplication.process_events
  end
  after(:context) { @qt_application.quit }
end

RSpec.describe Roded::Frontends::QtDocumentRenderer, "incremental content" do
  include_context "Qt native document rendering"

  it "preserves native blocks, Unicode, tabs and caret markers through edits and undo" do
    original = ["def привет", "\t🙂é<&", "", "end", ""]
    expect_native_frame(snapshot(original, { row: 1, col: 2 }))
    changed = original.dup
    changed[1] = "\t🙂🙂<&"
    expect_native_frame(snapshot(changed, { row: 1, col: changed[1].length }))
    expect_native_frame(snapshot(changed, { row: 3, col: 3 }))
    expect_native_frame(snapshot(original, { row: 0, col: 0 }))
  end

  it "preserves prefix and suffix blocks across insertions, deletions and empty-document transitions" do
    states = [[""], ["first", ""], ["new", "first", ""], ["new", "first", "middle", "last", ""],
              ["new", "last", ""], [""], ["🙂", "\t", "end"]]
    states.each { |lines| expect_native_frame(snapshot(lines, { row: lines.length - 1, col: lines.last.length })) }
  end

  it "moves the paragraph background with the caret across nonempty and empty lines" do
    lines = ["previous paragraph", "", "current paragraph", "next paragraph"]
    [0, 2, 1, 3, 2, 2].each do |row|
      expect_native_frame(snapshot(lines, { row:, col: [2, lines[row].length].min }))
    end
  end
end

RSpec.describe Roded::Frontends::QtDocumentRenderer, "structural indexes" do
  include_context "Qt native document rendering"

  it "keeps native offsets correct when an EOL marker changes before a structural edit" do
    expect_native_frame(snapshot(["prefix", "", "change", "last"], { row: 0, col: 6 }))
    expect_native_frame(snapshot(["prefix", "", "cha", "nge", "last"], { row: 1, col: 0 }))
    expect_native_frame(snapshot(["prefix", "", "new", "cha", "nge", "last"], { row: 0, col: 6 }))
  end
end

RSpec.describe Roded::Frontends::QtCursorMapper, "cached snapshot geometry" do
  include_context "Qt native document rendering"

  it "uses native block coordinates and cached Unicode lines without splitting the text" do
    state = snapshot(["one", "\t🙂界", "last"], { row: 1, col: 2 })
    expect_native_frame(state)
    @editor.resize(320, 160)
    @editor.show
    described_class.place(@editor, state, state[:text], row_position: @renderer.row_position(1))
    QApplication.process_events
    rectangle = @editor.cursor_rect
    opaque_text = Object.new
    point = described_class.position_at(@editor, rectangle.x, rectangle.y + 1, opaque_text, state)
    expect(point).to eq(state[:point])
    expected = @editor.font_metrics.horizontal_advance("  🙂", 4)
    expect(described_class.horizontal_offset(@editor, opaque_text, 1, 2, state)).to eq(expected)
  end
end

RSpec.describe Roded::Frontends::QtDocumentRenderer, "overlays and copies" do
  include_context "Qt native document rendering"

  it "removes selection and search highlights after their ranges change" do
    lines = ["def one", "two", "end"]
    state = snapshot(lines, { row: 2, col: 2 }, mark: { row: 0, col: 0 },
                                                highlight: { start: { row: 1, col: 0 }, finish: { row: 1, col: 3 } })
    expect_native_frame(state)
    expect(@editor.to_html).to include("background-color:#e5c07b", "background-color:#3e4451")
    expect_native_frame(snapshot(lines, { row: 0, col: 1 }))
    expect(@editor.to_html).not_to include("background-color:#e5c07b", "background-color:#3e4451")
  end

  it "keeps a split document and its UTF-16 index independent of subsequent source edits" do
    lines = ["🙂", "", "last"]
    state = snapshot(lines, { row: 0, col: 1 })
    expect_native_frame(state)
    copy = Roded::Frontends::QtDocumentRenderer.new(@reference)
    copy.copy_from(@renderer)
    copy.render(state, state[:text])
    copied_text = @reference.to_plain_text
    changed = snapshot(["a longer first line", "", "last"], { row: 0, col: 0 })
    @renderer.render(changed, changed[:text])
    expect(@reference.to_plain_text).to eq(copied_text)
    expect(copy.row_position(1)).to eq(4)
    expect(@renderer.row_position(1)).to eq(20)
  end
end

RSpec.describe Roded::Frontends::QtDocumentRenderer, "plain-layout split copies" do
  include_context "Qt native document rendering"

  it "copies rich fragments into independent plain-layout documents with different caret rows" do
    state = snapshot(["🙂first", "", "last"], { row: 0, col: 1 })
    expect_native_frame(state)
    original_text = @editor.to_plain_text
    target = Roded::Frontends::QtTextEditor.new
    copy = described_class.new(target)
    copy.copy_from(@renderer)
    changed = snapshot(state[:lines], { row: 2, col: 4 })
    copy.render(changed, changed[:text])
    @reference.set_html(Roded::Frontends::QtEditorHtmlRenderer.new(changed[:text], changed).render)
    expect(target.to_plain_text).to eq(@reference.to_plain_text)
    expect(target.document.handle).not_to eq(@editor.document.handle)
    expect(target.to_html.scan(/<(?:p|pre) [^>]*>/).map { |tag| tag.include?("background-color:#343a46") })
      .to eq([false, false, true])
    copied_text = target.to_plain_text
    expect(@editor.to_plain_text).to eq(original_text)
    expect_current_line_background(0)
    expect_native_frame(snapshot(["longer first", "", "last"], { row: 0, col: 0 }))
    expect(target.to_plain_text).to eq(copied_text)
  ensure
    target&.close
  end
end
