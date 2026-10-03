# rubocop:disable Metrics/BlockLength
RSpec.describe Roded::Buffer do
  subject(:buffer) { described_class.new("test") }

  let(:observer) { instance_double("Observer", update: nil) }

  before do
    buffer.add_observer(observer)
  end

  describe "#insert_char" do
    it "inserts a character at the cursor and advances the cursor" do
      buffer.insert_char("a")

      expect(buffer.lines).to eq(["a"])
      expect(buffer.cursor_pos).to eq({ row: 0, col: 1 })
      expect(observer).to have_received(:update).with(buffer)
    end

    it "ignores nil and empty input" do
      buffer.insert_char(nil)
      buffer.insert_char("")

      expect(buffer.lines).to eq([""])
      expect(observer).not_to have_received(:update)
    end
  end

  describe "text round trips" do
    it "preserves empty text, final newline, and CRLF" do
      expect(described_class.new.load_text("").to_s).to eq("")
      expect(described_class.new.load_text("alpha\nbeta\n").to_s).to eq("alpha\nbeta\n")
      expect(described_class.new.load_text("alpha\r\nbeta").to_s).to eq("alpha\r\nbeta")
      expect(described_class.new.load_text("Привет, мир!\n").to_s).to eq("Привет, мир!\n")
    end

    it "rejects mixed line endings and invalid UTF-8" do
      expect { described_class.new.load_text("a\nb\r\n") }
        .to raise_error(ArgumentError, /mixed line endings/)
      expect { described_class.new.load_text("\xFF".b.force_encoding(Encoding::UTF_8)) }
        .to raise_error(ArgumentError, /valid UTF-8/)
    end

    it "keeps at least one line and clamps cursor assignments" do
      buffer.lines = []
      buffer.cursor_pos = { row: 9, col: 9 }

      expect(buffer.lines).to eq([""])
      expect(buffer.cursor_pos).to eq({ row: 0, col: 0 })
      buffer.insert_char("a")
      expect(buffer.lines).to eq(["a"])
    end
  end

  describe "#backspace" do
    it "removes the character before the cursor" do
      buffer.lines = ["abc"]
      buffer.cursor_pos = { row: 0, col: 2 }

      buffer.backspace

      expect(buffer.lines).to eq(["ac"])
      expect(buffer.cursor_pos).to eq({ row: 0, col: 1 })
      expect(observer).to have_received(:update).with(buffer)
    end

    it "joins with the previous line at the start of a line" do
      buffer.lines = %w[abc def]
      buffer.cursor_pos = { row: 1, col: 0 }

      buffer.backspace

      expect(buffer.lines).to eq(["abcdef"])
      expect(buffer.cursor_pos).to eq({ row: 0, col: 3 })
    end
  end

  describe "#delete_char" do
    it "removes the character at the cursor" do
      buffer.lines = ["abc"]
      buffer.cursor_pos = { row: 0, col: 1 }

      buffer.delete_char

      expect(buffer.lines).to eq(["ac"])
      expect(buffer.cursor_pos).to eq({ row: 0, col: 1 })
      expect(observer).to have_received(:update).with(buffer)
    end

    it "joins with the next line at end of line" do
      buffer.lines = %w[abc def]
      buffer.cursor_pos = { row: 0, col: 3 }

      buffer.delete_char

      expect(buffer.lines).to eq(["abcdef"])
      expect(buffer.cursor_pos).to eq({ row: 0, col: 3 })
    end
  end

  describe "#newline" do
    it "splits the line at the cursor" do
      buffer.lines = ["abcd"]
      buffer.cursor_pos = { row: 0, col: 2 }

      buffer.newline

      expect(buffer.lines).to eq(%w[ab cd])
      expect(buffer.cursor_pos).to eq({ row: 1, col: 0 })
      expect(observer).to have_received(:update).with(buffer)
    end
  end

  describe "cursor movement" do
    before do
      buffer.lines = %w[abcd xy z]
      buffer.cursor_pos = { row: 0, col: 3 }
    end

    it "moves left and right within line bounds" do
      buffer.move_cursor_left
      buffer.move_cursor_left
      buffer.move_cursor_right

      expect(buffer.cursor_pos).to eq({ row: 0, col: 2 })
    end

    it "moves to line boundaries" do
      buffer.move_cursor_line_start
      expect(buffer.cursor_pos).to eq({ row: 0, col: 0 })

      buffer.move_cursor_line_end
      expect(buffer.cursor_pos).to eq({ row: 0, col: 4 })
    end

    it "clamps the column when moving between lines" do
      buffer.move_cursor_down
      expect(buffer.cursor_pos).to eq({ row: 1, col: 2 })

      buffer.move_cursor_down
      expect(buffer.cursor_pos).to eq({ row: 2, col: 1 })

      buffer.move_cursor_up
      expect(buffer.cursor_pos).to eq({ row: 1, col: 1 })
    end

    it "moves by page while clamping rows and columns" do
      buffer.move_cursor_page_down(2)
      expect(buffer.cursor_pos).to eq({ row: 2, col: 1 })

      buffer.move_cursor_page_up(5)
      expect(buffer.cursor_pos).to eq({ row: 0, col: 1 })
    end
  end

  describe "#kill_line" do
    let(:kill_ring) { Roded::KillRing.new }

    it "kills text from the cursor to the end of the line" do
      buffer.lines = ["abcdef"]
      buffer.cursor_pos = { row: 0, col: 2 }

      buffer.kill_line(kill_ring)

      expect(buffer.lines).to eq(["ab"])
      expect(kill_ring.last).to eq("cdef")
      expect(buffer.cursor_pos).to eq({ row: 0, col: 2 })
    end

    it "joins the next line when killing at end of line" do
      buffer.lines = %w[abc def]
      buffer.cursor_pos = { row: 0, col: 3 }

      buffer.kill_line(kill_ring)

      expect(buffer.lines).to eq(["abcdef"])
      expect(kill_ring.last).to be_nil
      expect(buffer.cursor_pos).to eq({ row: 0, col: 3 })
    end
  end

  describe "readonly mode" do
    before do
      buffer.lines = %w[abc def]
      buffer.cursor_pos = { row: 0, col: 1 }
      buffer.readonly = true
    end

    it "prevents text mutations" do
      buffer.insert_char("x")
      buffer.backspace
      buffer.delete_char
      buffer.newline
      buffer.kill_line(Roded::KillRing.new)

      expect(buffer.lines).to eq(%w[abc def])
      expect(buffer.cursor_pos).to eq({ row: 0, col: 1 })
      expect(observer).not_to have_received(:update)
    end
  end
end
# rubocop:enable Metrics/BlockLength
