require "spec_helper"
require "roded/frontends/curses"

RSpec.describe Roded::Frontends::Curses do
  it "wakes the input loop when the core publishes quit" do
    frontend = described_class.allocate
    logger = double
    wake_writer = double
    allow(frontend).to receive(:logger).and_return(logger)
    allow(logger).to receive(:debug)
    frontend.instance_variable_set(:@wake_w, wake_writer)
    expect(wake_writer).to receive(:write_nonblock).with(".").and_return(1)

    frontend.handle_command(Roded::Command.new(:quit, {}))
  end
end
