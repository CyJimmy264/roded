require "spec_helper"
require "roded/frontends/curses"

RSpec.describe Roded::Frontends::Curses do
  it "keeps the modeline above the reserved final row after a resize" do
    frontend = described_class.allocate
    height = 8
    screen = double(maxx: 20)
    allow(screen).to receive(:maxy) { height }
    %i[clear refresh setpos].each { |method| allow(screen).to receive(method) }
    %i[screen color_pairs minibuffer_state picker_state].zip([screen, {}, nil, nil]).each do |name, value|
      frontend.instance_variable_set("@#{name}", value)
    end
    lines = (1..8).map { |number| "Line #{number}" }
    item = { id: 1, text: lines.join("\n"), lines:, tokens: Array.new(8) { [] },
             point: { row: 0, col: 0 }, mark: nil, highlight: nil, name: "doc", mode: :plain,
             modified: false, readonly: false, active: true, top_line: 0, left_column: 0 }
    snapshot = { tree: { window_id: 1 }, active_window_id: 1, windows: [item] }
    rows = []
    modelines = []
    allow(frontend).to receive(:draw_buffer_line) { |context| rows << context.screen_row }
    allow(frontend).to receive(:draw_modeline) { |_item, row, *_arguments| modelines << row }

    frontend.send(:render_layout, snapshot)
    height = 5
    frontend.send(:render_layout, snapshot)

    expect(rows.last(3)).to eq([0, 1, 2])
    expect(modelines.last).to eq(3)
  end
end
