require "timeout"

RSpec.describe Roded::RubyHighlightWorker do
  it "returns only changed frozen rows from an isolated lexer process" do
    completed = Queue.new
    worker = described_class.new { |result| completed << result }
    lines = ["def greet", '  puts "🙂"', "end"].each(&:freeze).freeze
    tokens = Roded::SyntaxHighlighter.new.spans(:ruby, lines)
    signatures = tokens.map { |row| Roded::RubyHighlightFingerprint.call(row) }.freeze
    changed = lines.dup
    changed[1] = '  puts "界"; 42'.freeze
    id = worker.submit(buffer_id: 1, revision: 2, lines: changed.freeze, signatures:)
    result = Timeout.timeout(10) { completed.pop }
    expect(result).to include(id:, buffer_id: 1, revision: 2)
    expect(result[:changes].map(&:first)).to eq([1])
    expect(result[:changes][0][1]).to eq(Roded::SyntaxHighlighter.new.spans(:ruby, changed)[1])
    expect(result[:changes]).to be_frozen
    expect(result[:changes][0][1]).to be_frozen
    expect(result[:changes][0][1]).to all(be_frozen)
  ensure
    worker&.close
  end
end

RSpec.describe Roded::RubyHighlightWorker, "coalescing and shutdown" do
  it "supersedes queued revisions and closes the child instead of leaking work" do
    completed = Queue.new
    worker = described_class.new { |result| completed << result }
    lines = ["42".freeze].freeze
    100.times { |revision| worker.submit(buffer_id: 1, revision:, lines:, signatures: [nil].freeze) }
    result = Timeout.timeout(10) { completed.pop }
    expect(result[:revision]).to eq(99)
    pid = worker.instance_variable_get(:@pid)
    worker.close
    expect(worker.instance_variable_get(:@thread)).to be_nil
    expect { Process.kill(0, pid) }.to raise_error(Errno::ESRCH)
    expect(worker.submit(buffer_id: 1, revision: 100, lines:, signatures: [nil].freeze)).to be_nil
  ensure
    worker&.close
  end
end

RSpec.describe Roded::RubyHighlightWorker, "worker failure" do
  it "completes a failed request with an error and shuts down its child" do
    completed = Queue.new
    worker = described_class.new { |result| completed << result }
    allow(worker).to receive(:process_jobs).and_raise(IOError, "broken private pipe")
    id = worker.submit(buffer_id: 1, revision: 2, lines: ["42".freeze].freeze, signatures: [nil].freeze)
    result = Timeout.timeout(10) { completed.pop }
    expect(result).to include(id:, revision: 2, changes: [], error: "broken private pipe")
  ensure
    worker&.close
  end
end
