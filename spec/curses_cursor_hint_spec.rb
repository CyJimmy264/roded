require "spec_helper"
require "roded/frontends/curses"

RSpec.describe Roded::Frontends::Curses do
  it "does not redraw or scroll for legacy cursor hints" do
    frontend = described_class.allocate
    screen = double(maxy: 8, maxx: 20)
    allow(screen).to receive_messages(clear: nil, refresh: nil)
    frontend.instance_variable_set(:@screen, screen)
    frontend.instance_variable_set(:@top, 0)

    expect(frontend).not_to receive(:scroll_viewport_down)
    expect(frontend).not_to receive(:redraw)
    command = Roded::Command.new(:move_cursor, { direction: :down })

    frontend.handle_command(command)

    expect(frontend.instance_variable_get(:@top)).to eq(0)
  end
end
