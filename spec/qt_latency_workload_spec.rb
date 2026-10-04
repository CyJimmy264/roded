require_relative "../benchmark/roded/fixture"
require_relative "../benchmark/qt_latency/workload"

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
