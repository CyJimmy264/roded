require "spec_helper"
require "roded/frontends/curses"

RSpec.describe Roded::Frontends::Curses do
  it "renders and positions the cursor on the final newline row" do
    buffer = Roded::Buffer.new("doc")
    buffer.load_text("a\n")
    buffer.move_cursor_document_end
    item = {
      id: 1, text: buffer.to_s, lines: buffer.lines, tokens: [[], []],
      point: buffer.cursor_pos, mark: nil, highlight: nil, name: "doc", mode: :plain,
      modified: false, readonly: false, active: true, top_line: 0, left_column: 0
    }
    frontend = described_class.allocate
    screen = double
    allow(screen).to receive(:setpos)
    frontend.instance_variable_set(:@screen, screen)
    rendered_rows = []
    allow(frontend).to receive(:draw_buffer_line) do |_record, line, buffer_row, screen_row, *_|
      rendered_rows << [line, buffer_row, screen_row]
    end
    allow(frontend).to receive(:draw_modeline)

    frontend.send(:draw_window, item, 0, 0, 20, 4)

    expect(rendered_rows).to include(["", 1, 1])
    expect(screen).to have_received(:setpos).with(1, 0)
  end
end
