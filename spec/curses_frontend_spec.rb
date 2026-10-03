require "roded/frontends/curses"

RSpec.describe Roded::Frontends::Curses do
  subject(:frontend) { described_class.allocate }

  it "normalizes terminal NUL as C-SPC and control bytes as Emacs keys" do
    expect(frontend.send(:normalize_input, "\0")).to eq("C-SPC")
    expect(frontend.send(:normalize_input, "\u0001")).to eq("C-a")
    expect(frontend.send(:normalize_input, "Ж")).to eq("Ж")
  end
end
