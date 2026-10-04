require_relative "../benchmark/qt_latency/trace"

RSpec.describe Roded::Benchmarking::LatencyTrace do # rubocop:disable Metrics/BlockLength
  def snapshot(point:, text:)
    { active_window_id: 1, windows: [{ id: 1, point:, text: }] }
  end

  it "waits for the input snapshot instead of acknowledging an unrelated background render" do
    trace = described_class.new(nil)
    target = snapshot(point: { row: 5, col: 4 }, text: "new text")
    stale = snapshot(point: { row: 5, col: 3 }, text: "old text")
    trace.key_received("x")
    trace.mark(:core_started)
    trace.snapshot_posted(target)
    expect(trace).not_to receive(:emit)
    trace.widget_started(stale)
    trace.rendered(stale)
  end

  it "acknowledges a matching frame once and retains all phase timestamps" do
    trace = described_class.new(nil)
    target = snapshot(point: { row: 5, col: 4 }, text: "new text")
    trace.key_received("x")
    trace.mark(:core_started)
    trace.snapshot_posted(target)
    trace.widget_started(target)
    expect(trace).to receive(:emit).with("rendered", target, satisfy do |record|
      record[:sequence] == 1 && record[:key] == "x" &&
        record[:phases_ns].keys == %i[input_received core_started snapshot_posted widget_started widget_finished]
    end).once
    trace.rendered(target)
    trace.rendered(target)
  end

  it "allows a later syntax snapshot for the same point and immutable text" do
    trace = described_class.new(nil)
    text = "new text".freeze
    target = snapshot(point: { row: 5, col: 4 }, text:)
    recolored = snapshot(point: { row: 5, col: 4 }, text:).merge(tokens: [])
    trace.key_received("x")
    trace.snapshot_posted(target)
    trace.widget_started(recolored)
    expect(trace).to receive(:emit).with("rendered", recolored, hash_including(sequence: 1))
    trace.rendered(recolored)
  end

  it "does not reuse the previous key's target before the next key reaches core" do
    trace = described_class.new(nil)
    target = snapshot(point: { row: 5, col: 4 }, text: "new text")
    trace.key_received("x")
    trace.snapshot_posted(target)
    trace.widget_started(target)
    expect(trace).to receive(:emit).once
    trace.rendered(target)
    trace.key_received("x")
    trace.widget_started(target)
    trace.rendered(target)
  end
end
