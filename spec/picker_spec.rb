# rubocop:disable Metrics/BlockLength
RSpec.describe Roded::Picker do
  it "filters candidates by case-insensitive orderless query terms" do
    picker = described_class.new(["Open File", "Save Buffer", "buffer switch"])

    picker.update_query("FILE ope")

    expect(picker.candidates).to eq(["Open File"])
    expect(picker.selected).to eq("Open File")
  end

  it "moves through candidates and wraps around" do
    picker = described_class.new(%w[alpha beta gamma])

    picker.move(-1)

    expect(picker.selected).to eq("gamma")
    expect(picker.snapshot[:candidates]).to be_frozen
  end

  it "handles empty results and freezes snapshots" do
    picker = described_class.new(["alpha"])
    picker.update_query("missing")

    expect(picker.selected).to be_nil
    expect(picker.snapshot).to be_frozen
    expect(picker.candidates).to be_empty
  end

  it "does not implicitly accept the first item for an empty query" do
    picker = described_class.new(%w[quit undo])

    expect(picker.selected).to be_nil
    picker.move(1)
    expect(picker.selected).to eq("undo")
  end

  it "walks query history and restores the current draft" do
    picker = described_class.new(%w[open undo], history: %w[open undo])
    picker.update_query("draft")

    expect(picker.move_history(-1)).to eq("undo")
    expect(picker.move_history(-1)).to eq("open")
    expect(picker.move_history(1)).to eq("undo")
    expect(picker.move_history(1)).to eq("draft")
  end

  it "records only non-empty queries and avoids consecutive duplicates" do
    picker = described_class.new(%w[open undo])
    picker.update_query("open")
    picker.commit_query
    picker.commit_query
    picker.update_query("")
    picker.commit_query

    expect(picker.history).to eq(["open"])
    expect(picker.history).to be_frozen
  end

  it "matches Unicode query terms independent of order" do
    picker = described_class.new(["путь 🙂 файл", "другой путь"])

    picker.update_query("ФАЙЛ 🙂")

    expect(picker.candidates).to eq(["путь 🙂 файл"])
  end

  it "keeps the selected candidate visible in a bounded snapshot" do
    picker = described_class.new(20.times.map { |index| "candidate-#{index}" })
    picker.update_query("candidate")
    12.times { picker.move(1) }
    snapshot = picker.snapshot(limit: 3)

    expect(snapshot[:candidates].length).to eq(3)
    expect(snapshot[:candidates][snapshot[:selected_index]]).to eq(picker.selected)
  end
end

RSpec.describe Roded::PickerViewport do
  it "keeps the selected candidate visible in a short viewport" do
    result = described_class.slice(%w[a b c d e f], 5, limit: 2)

    expect(result).to eq(candidates: %w[e f], selected_index: 1)
  end

  it "returns no rows when the frontend has no candidate space" do
    result = described_class.slice(%w[a b], 1, limit: 0)

    expect(result).to eq(candidates: [], selected_index: 0)
  end
end
# rubocop:enable Metrics/BlockLength
