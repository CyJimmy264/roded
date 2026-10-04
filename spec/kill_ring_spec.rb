RSpec.describe Roded::KillRing do
  subject(:kill_ring) { described_class.new }

  it "combines consecutive pushes and separates a new kill sequence" do
    kill_ring.push("first")
    kill_ring.push("\n")

    expect(kill_ring.items).to eq(["first\n"])

    kill_ring.break_sequence
    kill_ring.push("next")

    expect(kill_ring.items.first).to eq("next")
    expect(kill_ring.items.last).to eq("first\n")
  end

  it "ignores empty kills without changing the sequence" do
    kill_ring.push("first")
    kill_ring.push("")
    kill_ring.push(" second")

    expect(kill_ring.last).to eq("first second")
  end
end
