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
end
