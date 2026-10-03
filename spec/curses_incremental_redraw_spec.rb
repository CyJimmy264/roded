require "spec_helper"
require "roded/frontends/curses"

module CursesIncrementalRedrawSpecSupport
  def self.snapshot(point, lines: %w[abc def])
    item = { id: 101, text: lines.join("\n"), lines:, tokens: Array.new(lines.length) { [] }, point:, mark: nil,
             highlight: nil, name: "doc", mode: :plain, modified: false, readonly: false,
             active: true, top_line: 0, left_column: 0 }
    { tree: { window_id: 101 }, active_window_id: 101, windows: [item] }
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
