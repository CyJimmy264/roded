require "spec_helper"
require "roded/frontends/curses"

module CursesRepeatRedrawSpecSupport
  def renderer
    screen = double(maxx: 80, maxy: 12)
    %i[clear erase refresh setpos addstr].each { |method| allow(screen).to receive(method) }
    allow(screen).to receive(:attron) { |_attribute, &block| block.call(screen) }
    frontend = Roded::Frontends::Curses.allocate
    frontend.send(:initialize_editor_state)
    frontend.instance_variable_set(:@screen, screen)
    [frontend, screen]
  end

  def snapshot(row: 8, top: 0, split: false)
    lines = Array.new(40) { |index| "line #{index}" }
    first = { id: 1, name: "first", lines:, point: { row:, col: 0 }, top_line: top, left_column: 0,
              mark: nil, highlight: nil, active: true, mode: :plain }
    second = first.merge(id: 2, name: "second", active: false, point: { row: 0, col: 0 }, top_line: 0)
    tree = split ? { direction: :vertical, first: { window_id: 1 }, second: { window_id: 2 } } : { window_id: 1 }
    { tree:, active_window_id: 1, windows: split ? [first, second] : [first] }
  end
end

RSpec.describe Roded::Application, "navigation at a document boundary" do
  it "leaves point, mark, highlight, viewport, history and frontend untouched on repeated C-p" do
    application = described_class.new
    application.startup
    application.current_buffer.load_text("abc\ndef")
    window = application.current_window
    window.point = { row: 0, col: 2 }
    window.mark = { row: 1, col: 1 }
    window.highlight = { start: { row: 0, col: 0 }, finish: { row: 0, col: 2 } }
    frontend = double(handle_command: nil)
    application.add_frontend(frontend)
    before = application.editor_snapshot
    expect(frontend).not_to receive(:handle_command)
    expect(window).not_to receive(:move_cursor_up)
    expect(application.current_buffer).not_to receive(:break_typing_undo_group)
    50.times { application.handle_event(Roded::InputEvent.new(:key, { key: "C-p" })) }
    expect(application.editor_snapshot).to eq(before)
  end
end

RSpec.describe Roded::Frontends::Curses, "changed-pane redraw" do
  include CursesRepeatRedrawSpecSupport

  it "does not redraw identical frames" do
    frontend, screen = renderer
    frame = snapshot
    frontend.send(:render_layout, frame)
    expect(screen).not_to receive(:clear)
    expect(screen).not_to receive(:erase)
    expect(screen).not_to receive(:refresh)
    frontend.send(:render_layout, frame)
  end

  it "redraws a scrolling pane without clearing the terminal or touching another pane and minibuffer" do
    frontend, screen = renderer
    frontend.send(:render_layout, snapshot(split: true))
    writes = []
    allow(frontend).to receive(:draw_window).and_wrap_original do |original, item, rectangle|
      writes << item[:id]
      original.call(item, rectangle)
    end
    expect(screen).not_to receive(:clear)
    expect(screen).not_to receive(:erase)
    expect(frontend).not_to receive(:render_overlays)
    frontend.send(:render_layout, snapshot(row: 12, top: 3, split: true))
    expect(writes).to eq([1])
    expect(screen).to have_received(:setpos).with(9, 0).at_least(:once)
  end
end

RSpec.describe Roded::Frontends::Curses, "explicit and structural refresh" do
  include CursesRepeatRedrawSpecSupport

  it "restores the active caret after drawing a later inactive pane and honors explicit refresh" do
    frontend, screen = renderer
    positions = []
    allow(screen).to receive(:setpos) { |row, col| positions << [row, col] }
    frame = snapshot(row: 1, split: true)
    frontend.send(:render_layout, frame)
    expect(positions.last).to eq([1, 0])
    expect(screen).to receive(:clear).once
    frontend.handle_command(Roded::UIUpdate.new(:render, { editor_snapshot: frame, force_redraw: true }))
    expect(positions.last).to eq([1, 0])
  end

  it "rebuilds geometry after a terminal resize even with an unchanged snapshot" do
    frontend, screen = renderer
    frame = snapshot(row: 8)
    frontend.send(:render_layout, frame)
    allow(screen).to receive(:maxy).and_return(6)
    expect(screen).to receive(:erase).once
    frontend.send(:render_layout, frame)
    expect(screen).to have_received(:setpos).with(3, 0).at_least(:once)
  end
end
