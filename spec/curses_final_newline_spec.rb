require "spec_helper"
require "roded/frontends/curses"

RSpec.describe Roded::Frontends::Curses do
  it "renders and positions the cursor on the final newline row" do
    buffer = Roded::Buffer.new("doc")
    buffer.load_text("a\n")
    window = Roded::Window.new(buffer).tap(&:move_cursor_document_end)
    item = {
      id: 1, text: buffer.to_s, lines: buffer.lines, tokens: [[], []],
      point: window.point, mark: nil, highlight: nil, name: "doc", mode: :plain,
      modified: false, readonly: false, active: true, top_line: 0, left_column: 0
    }
    frontend = described_class.allocate
    screen = double(setpos: nil)
    frontend.instance_variable_set(:@screen, screen)
    rendered_rows = []
    allow(frontend).to receive(:draw_buffer_line) do |context|
      rendered_rows << [context.line, context.buffer_row, context.screen_row]
    end
    allow(frontend).to receive(:draw_modeline)

    rectangle = Roded::Frontends::CursesRenderContext::Rectangle.new(
      window_id: 1, left: 0, top: 0, width: 20, height: 4
    )
    frontend.send(:draw_window, item, rectangle)
    frontend.send(:place_active_layout_cursor, { active_window_id: 1 }, { 1 => item }, [rectangle])

    expect(rendered_rows).to include(["", 1, 1])
    expect(screen).to have_received(:setpos).with(1, 0)
  end
end
