require_relative "../benchmark/roded/fixture"
require "spec_helper"
require_relative "../benchmark/qt_latency/workload"
require_relative "../benchmark/qt_latency/file_fixture"

RSpec.describe Roded::Benchmarking::LatencyWorkload, "word movement oracle" do
  %w[plain ruby unicode].each do |profile|
    it "checks the first word boundaries and rejects changes to its text in #{profile}" do
      fixture = Roded::Benchmarking::Fixture.new(line_count: 1500, profile:)
      oracle = described_class.new("word", fixture, page_size: 36)
      line = fixture.text.split("\n").fetch(750)
      record = { "point" => { "row" => 750, "col" => 10 }, "line" => line, "top_line" => 740 }
      oracle.verify(record, "cursor.word_forward")
      record["point"] = { "row" => 750, "col" => 0 }
      oracle.verify(record, "cursor.word_backward")
      record["point"] = { "row" => 750, "col" => 10 }
      record["line"] = "changed text"

      expect { oracle.verify(record, "cursor.word_forward") }.to raise_error("key changed the wrong text")
    end
  end
end

RSpec.describe Roded::Benchmarking::LatencyWorkload, "page movement oracle" do
  let(:fixture) { Roded::Benchmarking::Fixture.new(line_count: 1500, profile: "plain") }

  def page_record(row, origin)
    { "point" => { "row" => row, "col" => 4 }, "line" => fixture.text.split("\n").fetch(row),
      "top_line" => origin }
  end

  it "checks repeated native-size page steps and the resulting viewport origin" do
    oracle = described_class.new("page", fixture, page_size: 36)
    oracle.verify(page_record(786, 751), "cursor.page_down")
    oracle.verify(page_record(750, 750), "cursor.page_up")
    oracle.verify(page_record(786, 751), "cursor.page_down")
    oracle.verify(page_record(750, 750), "cursor.page_up")
  end

  it "rejects a wrong page step even when the painted caret moved" do
    oracle = described_class.new("page", fixture, page_size: 36)

    expect { oracle.verify(page_record(788, 751), "cursor.page_down") }.to raise_error(/unexpected point/)
  end
end

RSpec.describe Roded::Benchmarking::LatencyWorkload, "viewport oracle" do
  it "rejects stale scrolling with the correct page destination" do
    fixture = Roded::Benchmarking::Fixture.new(line_count: 1500, profile: "plain")
    oracle = described_class.new("page", fixture, page_size: 36)
    record = { "point" => { "row" => 786, "col" => 4 }, "line" => fixture.text.split("\n").fetch(786),
               "top_line" => 740 }

    expect { oracle.verify(record, "cursor.page_down") }.to raise_error("unexpected viewport origin")
  end
end

RSpec.describe Roded::Benchmarking::LatencyWordCursor do
  it "crosses punctuation, blank rows and Unicode words in either direction" do
    lines = ["alpha!", "", "\tстрока_42 界 end"]
    forward = described_class.new(lines, { "row" => 0, "col" => 6 }).forward
    expect(forward).to eq("row" => 2, "col" => 10)
    expect(described_class.new(lines, { "row" => 2, "col" => 1 }).backward).to eq("row" => 0, "col" => 0)
  end

  it "checks word boundaries deep inside a line of more than 1000 characters" do
    line = "word " * 500
    expect(described_class.new([line], { "row" => 0, "col" => 1201 }).forward).to eq("row" => 0, "col" => 1204)
    expect(described_class.new([line], { "row" => 0, "col" => 1204 }).backward).to eq("row" => 0, "col" => 1200)
  end
end

RSpec.describe Roded::Benchmarking::LatencyFileFixture do
  it "preserves a real document and its final empty line without modifying it" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "sample.md")
      File.write(path, "heading\ntext\n")
      fixture = described_class.new(path)
      expect(fixture.line_count).to eq(3)
      expect(fixture.mode).to eq(:markdown)
      expect(fixture.metadata[:sha256]).to eq(Digest::SHA256.hexdigest(File.read(path)))
      expect(File.read(path)).to eq("heading\ntext\n")
    end
  end
end
