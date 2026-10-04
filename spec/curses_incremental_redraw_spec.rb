require "spec_helper"
require "roded/frontends/curses"

module CursesIncrementalRedrawSpecSupport
  def self.snapshot(point, lines: %w[abc def])
    item = { id: 101, text: lines.join("\n"), lines:, tokens: Array.new(lines.length) { [] }, point:, mark: nil,
             highlight: nil, name: "doc", mode: :plain, modified: false, readonly: false,
             active: true, top_line: 0, left_column: 0 }
    { tree: { window_id: 101 }, active_window_id: 101, windows: [item] }
  end

  def editor_state(application)
    window = application.current_window
    buffer = application.current_buffer
    [application.editor_snapshot, buffer.to_s, buffer.modified?, window.point, window.mark,
     window.top_line, window.left_column]
  end

  def build_renderer
    screen = double(maxy: 10, maxx: 60)
    %i[clear setpos refresh addstr].each { |method| allow(screen).to receive(method) }
    allow(screen).to receive(:attron) { |_attribute, &block| block.call(screen) }
    frontend = Roded::Frontends::Curses.allocate
    { screen:, color_pairs: {}, minibuffer_state: nil, picker_state: nil }.each do |name, value|
      frontend.instance_variable_set("@#{name}", value)
    end
    allow(frontend).to receive(:draw_buffer_line)
    frontend
  end
end

RSpec.describe Roded::Frontends::Curses, "incremental cursor redraw" do
  it "redraws only the old and new cursor rows during navigation" do
    writes = []
    screen = double(maxy: 8, maxx: 20)
    %i[clear setpos refresh].each { |method| allow(screen).to receive(method) }
    allow(screen).to receive(:addstr) { |text| writes << text }
    allow(screen).to receive(:attron) { |_attribute, &block| block.call(screen) }
    frontend = described_class.allocate
    { screen:, color_pairs: {}, minibuffer_state: nil, picker_state: nil }.each do |name, value|
      frontend.instance_variable_set("@#{name}", value)
    end

    frontend.send(:render_layout, CursesIncrementalRedrawSpecSupport.snapshot({ row: 0, col: 1 }))
    writes.clear
    expect(screen).not_to receive(:clear)
    frontend.send(:render_layout, CursesIncrementalRedrawSpecSupport.snapshot({ row: 1, col: 2 }))

    expect(writes).to include("abc", "def", "* doc  plain  2:3")
  end
end

RSpec.describe Roded::Frontends::Curses, "horizontal cursor scrolling" do
  it "redraws the full layout when horizontal scrolling changes its origin" do
    screen = double(maxy: 6, maxx: 8)
    %i[clear setpos refresh].each { |method| allow(screen).to receive(method) }
    allow(screen).to receive(:addstr)
    allow(screen).to receive(:attron) { |_attribute, &block| block.call(screen) }
    frontend = described_class.allocate
    { screen:, color_pairs: {}, minibuffer_state: nil, picker_state: nil }.each do |name, value|
      frontend.instance_variable_set("@#{name}", value)
    end
    redraws = []
    allow(frontend).to receive(:draw_buffer_line) { |context| redraws << [context.buffer_row, context.left_column] }

    lines = ["0123456789abcdef", "second visible row"]
    frontend.send(:render_layout, CursesIncrementalRedrawSpecSupport.snapshot({ row: 0, col: 0 }, lines:))
    redraws.clear
    frontend.send(:render_layout, CursesIncrementalRedrawSpecSupport.snapshot({ row: 0, col: 12 }, lines:))

    expect(redraws.map(&:first)).to contain_exactly(0, 1)
    expect(redraws.map(&:last).uniq).to eq([5])
  end
end

RSpec.describe Roded::Frontends::Curses, "snapshot rendering" do
  include CursesIncrementalRedrawSpecSupport

  it "does not change document or view state in the core" do
    application = Roded::Application.new
    application.startup
    window = application.current_window
    buffer = application.current_buffer
    buffer.insert_text("first line\nsecond line", at: window.point)
    window.point = { row: 1, col: 4 }
    window.mark = { row: 0, col: 2 }
    window.top_line = 0
    window.left_column = 0
    snapshot = application.editor_snapshot
    before = editor_state(application)
    frontend = build_renderer

    3.times { frontend.send(:render_layout, snapshot) }

    expect(application.editor_snapshot).to eq(snapshot)
    expect(buffer.to_s).to eq("first line\nsecond line")
    expect(buffer.modified?).to be(true)
    expect(window.point).to eq(row: 1, col: 4)
    expect(window.mark).to eq(row: 0, col: 2)
    expect(window.top_line).to eq(0)
    expect(window.left_column).to eq(0)
    expect(editor_state(application)).to eq(before)
  end
end
