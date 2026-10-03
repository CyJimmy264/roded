require "roded/frontends/curses"

RSpec.describe Roded::Frontends::Curses do
  it "renders syntax segments when curses attron yields its window" do
    screen = double(maxy: 24, maxx: 80)
    allow(screen).to receive(:setpos)
    allow(screen).to receive(:attron) { |_attribute, &block| block.call(screen) }
    allow(Curses).to receive(:color_pair).with(3).and_return(3)
    expect(screen).to receive(:addstr).with("def")

    frontend = described_class.allocate
    frontend.instance_variable_set(:@screen, screen)
    frontend.instance_variable_set(:@color_pairs, { keyword: 3 })
    token = { start: 0, finish: 3, category: :keyword }

    frontend.send(:write_styled_segment, nil, 0, 0, "def answer", 0, 3, 10, [token], nil, 0)
  end
end
