require "spec_helper"
require_relative "../lib/roded/frontends/qt"

RSpec.shared_context "queued Qt dispatcher" do
  let(:timer) { double("GUI timer", handle: Object.new, set_interval: nil, set_single_shot: nil, stop: nil) }
  let(:view) { double(render_layout: nil, display_message: nil) }
  let(:dispatcher) { described_class.new(view, Object.new, Object.new) }
  let(:wakeups) { [] }

  before do
    allow(QTimer).to receive(:new).and_return(timer)
    allow(timer).to receive(:connect) { |_signal, &callback| @timeout = callback }
    allow(Qt::Native).to receive(:qtimer_single_shot) { |*arguments| wakeups << arguments }
  end
end

RSpec.describe Roded::Frontends::QtUiDispatcher, "event-driven wakeup" do
  include_context "queued Qt dispatcher"

  it "leaves an empty queue asleep and requests one GUI wakeup for a burst" do
    dispatcher.start
    expect(wakeups).to be_empty
    500.times { |revision| dispatcher.post(:layout, { revision: }) }
    dispatcher.post(:message, "saved")

    expect(wakeups).to eq([[timer.handle, 0, timer.handle, "1start()"]])
    expect(timer).to have_received(:set_interval).with(0)
    expect(timer).to have_received(:set_single_shot).with(true)
    @timeout.call(nil)
    expect(view).to have_received(:render_layout).once.with(revision: 499)
    expect(view).to have_received(:display_message).once.with("saved")
    expect(wakeups.size).to eq(1)
  end
end

RSpec.describe Roded::Frontends::QtUiDispatcher, "updates during delivery" do
  include_context "queued Qt dispatcher"

  it "queues another wakeup for an update published during widget application" do
    allow(view).to receive(:display_message) do |message|
      dispatcher.post(:message, "next") if message == "first"
    end
    dispatcher.start
    dispatcher.post(:message, "first")
    @timeout.call(nil)

    expect(wakeups.size).to eq(2)
    expect(view).not_to have_received(:display_message).with("next")
    @timeout.call(nil)
    expect(view).to have_received(:display_message).once.with("next")
  end
end

RSpec.describe Roded::Frontends::QtUiDispatcher, "stale wakeup after stopping" do
  include_context "queued Qt dispatcher"

  it "keeps queued actions when a stale wakeup arrives after stopping" do
    dispatcher.start
    dispatcher.post(:message, "pending")
    dispatcher.stop
    @timeout.call(nil)
    expect(view).not_to have_received(:display_message)

    dispatcher.start
    expect(wakeups.size).to eq(2)
    @timeout.call(nil)
    expect(view).to have_received(:display_message).once.with("pending")
  end
end

RSpec.describe Roded::Frontends::QtUiDispatcher, "manual delivery" do
  include_context "queued Qt dispatcher"

  it "allows manual draining while automatic delivery is stopped" do
    dispatcher.post(:message, "manual")
    dispatcher.send(:drain)

    expect(wakeups).to be_empty
    expect(view).to have_received(:display_message).once.with("manual")
    dispatcher.start
    expect(wakeups).to be_empty
  end
end
