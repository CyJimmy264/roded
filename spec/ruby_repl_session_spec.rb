RSpec.describe Roded::RubyReplSession, "persistent binding" do
  let(:events) { Queue.new }
  subject(:session) { described_class.new(Object.new) { |event| events << event } }

  it "keeps a persistent binding and records history" do
    expect(session.start_evaluation?("answer = 40")).to be(true)
    first = events.pop
    session.thread.join
    expect(first.payload[:result]).to eq("40")

    session.start_evaluation?("answer + 2")
    second = events.pop
    session.thread.join
    expect(second.payload[:result]).to eq("42")
    expect(session.history).to eq(["answer = 40", "answer + 2"])
  end

  it "evaluates multiline Ruby input in the shared binding" do
    session.start_evaluation?("total = 1\ntotal += 2\ntotal")
    result = events.pop.payload
    session.thread.join

    expect(result[:result]).to eq("3")
  end
end

RSpec.describe Roded::RubyReplSession, "output and errors" do
  let(:events) { Queue.new }
  subject(:session) { described_class.new(Object.new) { |event| events << event } }

  it "captures puts and reports exceptions without ending the session" do
    session.start_evaluation?("puts 'hello'")
    output = events.pop.payload
    session.thread.join
    expect(output[:stdout]).to eq("hello\n")
    expect(output[:stderr]).to eq("")
    expect(output[:result]).to eq("nil")

    session.start_evaluation?("raise 'broken'")
    error = events.pop.payload
    session.thread.join
    expect(error[:error]).to eq("RuntimeError: broken")

    session.start_evaluation?("warn 'warning'")
    warning = events.pop.payload
    session.thread.join
    expect(warning[:stderr]).to eq("warning\n")

    session.start_evaluation?("$stdout.write('out'); $stderr.write('err')")
    streams = events.pop.payload
    session.thread.join
    expect(streams[:stdout]).to eq("out")
    expect(streams[:stderr]).to eq("err")
  end
end

RSpec.describe Roded::RubyReplSession, "lifecycle" do
  let(:events) { Queue.new }
  subject(:session) { described_class.new(Object.new) { |event| events << event } }

  it "handles exit and interrupts an active evaluation" do
    session.start_evaluation?("exit")
    exit_result = events.pop.payload
    session.thread.join
    expect(exit_result[:exit]).to be(true)

    session.start_evaluation?("loop {}")
    expect(session.interrupt).to be(true)
    interrupt = events.pop.payload
    session.thread.join
    expect(interrupt[:error]).to eq("Interrupt")
  end
end
