require "spec_helper"
require_relative "../benchmark/typing_stream"

RSpec.describe Roded::Benchmarking::TypingStreamRunner do
  it "measures consecutive edits within a sample and starts a fresh document for the next sample" do
    points = []
    config = { lines: [1500], layers: ["application"], profile: "plain", buffers: 1,
               windows: 1, samples: 2, iterations: 3, warmup: 0, seed: 1 }
    scenario = Roded::Benchmarking::Scenario.new(
      "edit.typing_stream", ->(_work) {},
      lambda { |work|
        points << work.window.point[:col]
        work.dispatch(:insert_char, char: "x")
      }, ->(work) { work.buffer.modified? }
    )
    report = described_class.new(config, output: StringIO.new).run([scenario])
    expect(points).to eq([12, 13, 14, 12, 13, 14])
    expect(report[:results].first[:samples].map(&:length)).to eq([3, 3])
    expect(report[:results].first[:metrics][:operations]).to eq(6)
  end
end

RSpec.describe Roded::Benchmarking::TypingStream do
  it "rejects unsupported layers, modes and nonpositive repetition counts" do
    [["--mode", "unknown"], ["--layer", "invalid"], ["--iterations", "0"], ["--lines", "10"]].each do |arguments|
      expect { described_class.new(arguments) }.to raise_error(OptionParser::InvalidArgument)
    end
  end
end
