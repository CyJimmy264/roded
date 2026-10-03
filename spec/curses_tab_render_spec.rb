require "spec_helper"
require "roded/frontends/curses"

RSpec.describe Roded::Frontends::Curses do
  it "writes expanded tabs while drawing a buffer row" do
    screen = double(maxy: 8, maxx: 20)
    allow(screen).to receive(:setpos)
    frontend = described_class.allocate
    frontend.instance_variable_set(:@screen, screen)
    frontend.instance_variable_set(:@color_pairs, {})
    item = { tokens: nil, mark: nil, point: { row: 0, col: 0 }, highlight: nil, lines: ["a\tb"] }

    expect(screen).to receive(:addstr).with("a b")
    frontend.send(:draw_buffer_line, item, "a\tb", 0, 0, 0, 20, 0)
  end
end
