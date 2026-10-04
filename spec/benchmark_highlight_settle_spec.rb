require_relative "../benchmark/roded/workspace"
require_relative "../benchmark/roded/fixture"

RSpec.describe Roded::Benchmarking::Workspace, "deferred syntax settling" do
  it "handles queued viewport feedback and finishes the latest syntax revision outside foreground timing" do
    fixture = Roded::Benchmarking::Fixture.new(line_count: 1500, profile: "ruby")
    work = described_class.new(layer: "application", fixture:, buffer_count: 1, window_count: 1)
    work.render
    work.application.push_event(Roded::InputEvent.new(:resize, {}))
    work.application.push_event(Roded::InputEvent.new(:horizontal_scroll,
                                                      { window_id: work.window.object_id, left_column: 2 }))
    work.dispatch(:insert_char, char: "X")
    expect(work.application.syntax_highlighting_pending?).to be(true)
    expect(work.settle_highlighting).to be_positive
    expect(work.application.syntax_highlighting_pending?).to be(false)
    expect(work.settle_highlighting).to be_nil
    tokens = work.application.editor_snapshot[:windows].first[:tokens]
    expect(tokens).to eq(Roded::SyntaxHighlighter.new.spans(:ruby, work.buffer.lines))
  ensure
    work&.close
  end
end

RSpec.describe Roded::Benchmarking::Workspace, "feedback reset" do
  it "processes old viewport feedback before restoring the next operation's initial position" do
    fixture = Roded::Benchmarking::Fixture.new(line_count: 1500, profile: "plain")
    work = described_class.new(layer: "application", fixture:, buffer_count: 1, window_count: 1)
    work.application.push_event(Roded::InputEvent.new(:horizontal_scroll,
                                                      { window_id: work.window.object_id, left_column: 25 }))
    work.reset
    expect(work.window.left_column).to eq(0)
    expect(work.application.instance_variable_get(:@event_queue)).to be_empty
  ensure
    work&.close
  end
end
