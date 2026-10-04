RSpec.describe Roded::RubyHighlightState do
  it "clears edited rows, maps unchanged suffixes and ignores superseded results" do
    lines = ["42", '"🙂"', "end"].each(&:freeze).freeze
    tokens = Roded::SyntaxHighlighter.new.spans(:ruby, lines)
    state = described_class.new(1, lines, tokens)
    changed = [lines[0], '"界"'.freeze, "7".freeze, lines[2]].freeze
    preview = state.prepare(2, changed)
    expect(preview).to eq([tokens[0], [], [], tokens[2]])
    state.submitted(10)
    state.prepare(3, lines)
    state.submitted(11)
    expect(state.apply(10, [])).to be(false)
    fresh = Roded::SyntaxHighlighter.new.spans(:ruby, lines)
    delta = [1, 2].map { |row| [row, fresh[row], Roded::RubyHighlightFingerprint.call(fresh[row])] }
    expect(state.apply(11, delta)).to be(true)
    expect(state.tokens).to eq(fresh)
    expect(state.tokens[0]).to equal(tokens[0])
    expect(state.tokens).to be_frozen
    expect(state.job_id).to be_nil
  end
end

RSpec.describe Roded::RubyHighlightState, "failed lexical results" do
  it "clears temporary colors instead of retaining stale context after a worker failure" do
    lines = ["42", '"🙂"'].each(&:freeze).freeze
    state = described_class.new(1, lines, Roded::SyntaxHighlighter.new.spans(:ruby, lines))
    state.prepare(2, lines)
    state.submitted(1)
    expect(state.apply(1, [], failed: true)).to be(true)
    expect(state.tokens).to eq([[], []])
    expect(state.tokens).to be_frozen
    expect(state.job_id).to be_nil
  end
end
