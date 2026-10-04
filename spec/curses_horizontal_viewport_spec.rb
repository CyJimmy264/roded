require "spec_helper"
require "roded/frontends/curses"

RSpec.describe Roded::Frontends::CursesHorizontalViewport do
  let(:viewport) { described_class.new }
  let(:item) do
    { id: 1, name: "long.txt", lines: ["a" * 1200], point: { row: 0, col: 339 }, left_column: 0 }
  end

  it "moves the displayed caret left on the first backward character after scrolling right" do
    expect(viewport.origin(item, 80)).to eq(260)
    item[:point][:col] += 1
    expect(viewport.origin(item, 80)).to eq(261)
    item[:point][:col] -= 1
    expect(viewport.origin(item, 80)).to eq(261)
    expect(item[:point][:col] - viewport.origin(item, 80)).to eq(78)
  end

  it "honors explicit horizontal scrolling and returns to the start of a line" do
    viewport.origin(item, 80)
    item[:left_column] = 300
    expect(viewport.origin(item, 80)).to eq(300)
    item[:point][:col] = 0
    expect(viewport.origin(item, 80)).to eq(0)
  end
end

RSpec.describe Roded::Frontends::CursesHorizontalViewport, "view lifetime" do
  let(:viewport) { described_class.new }
  let(:item) do
    { id: 1, name: "long.txt", lines: ["a" * 1200], point: { row: 0, col: 339 }, left_column: 0 }
  end

  it "keeps different windows independent and discards closed views" do
    viewport.origin(item, 80)
    second = item.merge(id: 2, point: { row: 0, col: 10 })
    expect(viewport.origin(second, 80)).to eq(0)
    viewport.retain([second])
    item[:point][:col] = 338
    expect(viewport.origin(item, 80)).to eq(259)
  end

  it "resets the derived origin when switching buffers" do
    item[:buffer_id] = 1
    viewport.origin(item, 80)
    item[:buffer_id] = 2
    item[:point][:col] = 338
    expect(viewport.origin(item, 80)).to eq(259)
  end
end

RSpec.describe Roded::Frontends::Curses, "backward cursor after horizontal scrolling" do
  it "places the screen cursor one cell left after a single backward move" do
    screen = double(maxy: 8, maxx: 80)
    %i[clear refresh addstr].each { |method| allow(screen).to receive(method) }
    positions = []
    allow(screen).to receive(:setpos) { |row, col| positions << [row, col] }
    allow(screen).to receive(:attron) { |_attribute, &block| block.call(screen) }
    frontend = described_class.allocate
    { screen:, color_pairs: {}, minibuffer_state: nil, picker_state: nil }.each do |name, value|
      frontend.instance_variable_set("@#{name}", value)
    end
    allow(frontend).to receive(:draw_buffer_line)
    lines = ["a" * 1200]
    make_snapshot = lambda do |col|
      item = { id: 1, name: "doc", lines:, point: { row: 0, col: }, top_line: 0, left_column: 0,
               mark: nil, highlight: nil, active: true, mode: :plain }
      { tree: { window_id: 1 }, active_window_id: 1, windows: [item] }
    end
    frontend.send(:render_layout, make_snapshot.call(339))
    frontend.send(:render_layout, make_snapshot.call(340))
    expect(positions.last).to eq([0, 79])
    expect(screen).not_to receive(:clear)
    frontend.send(:render_layout, make_snapshot.call(339))
    expect(positions.last).to eq([0, 78])
  end
end
