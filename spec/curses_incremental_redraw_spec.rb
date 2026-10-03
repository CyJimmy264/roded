require "spec_helper"
require "roded/frontends/curses"

RSpec.describe Roded::Frontends::Curses do
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
    snapshot = lambda do |point|
      item = { id: 101, text: "abc\ndef", lines: %w[abc def], tokens: [[], []], point:, mark: nil,
               highlight: nil, name: "doc", mode: :plain, modified: false, readonly: false,
               active: true, top_line: 0, left_column: 0 }
      { tree: { window_id: 101 }, active_window_id: 101, windows: [item] }
    end

    frontend.send(:render_layout, snapshot.call(row: 0, col: 1))
    writes.clear
    expect(screen).not_to receive(:clear)
    frontend.send(:render_layout, snapshot.call(row: 1, col: 2))

    expect(writes).to include("abc", "def", "* doc  plain  2:3")
  end
end
