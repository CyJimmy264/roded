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
      expect(observer).to have_received(:update).with(buffer).at_least(:once)
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

    it "exposes a final newline as an editable empty row" do
      buffer.load_text("alpha\n")

      expect(buffer.lines).to eq(["alpha", ""])
      buffer.move_cursor_document_end
      expect(buffer.cursor_pos).to eq({ row: 1, col: 0 })

      buffer.insert_char("x")
      expect(buffer.to_s).to eq("alpha\nx")
      expect(buffer.lines).to eq(%w[alpha x])
      expect(buffer.undo).to be(true)
      expect(buffer.to_s).to eq("alpha\n")
      expect(buffer.cursor_pos).to eq({ row: 1, col: 0 })
    end

    it "adds another blank row when newline is inserted at the final row" do
      buffer.load_text("alpha\n")
      buffer.move_cursor_document_end

      buffer.newline

      expect(buffer.lines).to eq(["alpha", "", ""])
      expect(buffer.to_s).to eq("alpha\n\n")
      expect(buffer.cursor_pos).to eq({ row: 2, col: 0 })
    end

    it "removes the final newline when backspace is pressed on its empty row" do
      buffer.load_text("alpha\n")
      buffer.move_cursor_document_end

      buffer.backspace

      expect(buffer.lines).to eq(["alpha"])
      expect(buffer.to_s).to eq("alpha")
      expect(buffer.cursor_pos).to eq({ row: 0, col: 5 })
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

  it "returns immutable snapshots instead of exposing document internals" do
    buffer.load_text("abc")

    expect(buffer.lines).to be_frozen
    expect(buffer.lines.first).to be_frozen
    expect(buffer.cursor_pos).to be_frozen
    expect(buffer.line_at_cursor).to be_frozen
    expect { buffer.lines.first << "changed" }.to raise_error(FrozenError)
    expect(buffer.to_s).to eq("abc")
  end

  describe "#backspace" do
    it "removes the character before the cursor" do
      buffer.lines = ["abc"]
      buffer.cursor_pos = { row: 0, col: 2 }

      buffer.backspace

      expect(buffer.lines).to eq(["ac"])
      expect(buffer.cursor_pos).to eq({ row: 0, col: 1 })
      expect(observer).to have_received(:update).with(buffer).at_least(:once)
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
      expect(observer).to have_received(:update).with(buffer).at_least(:once)
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
      expect(observer).to have_received(:update).with(buffer).at_least(:once)
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

    it "moves by Unicode words and reaches document boundaries" do
      buffer.load_text("one two\nПривет-world")

      buffer.move_cursor_word_forward
      expect(buffer.cursor_pos).to eq({ row: 0, col: 3 })
      buffer.move_cursor_word_forward
      expect(buffer.cursor_pos).to eq({ row: 0, col: 7 })
      buffer.move_cursor_word_forward
      expect(buffer.cursor_pos).to eq({ row: 1, col: 6 })
      buffer.move_cursor_word_backward
      expect(buffer.cursor_pos).to eq({ row: 1, col: 0 })
      buffer.move_cursor_document_end
      expect(buffer.cursor_pos).to eq({ row: 1, col: 12 })
      buffer.move_cursor_document_start
      expect(buffer.cursor_pos).to eq({ row: 0, col: 0 })
    end
  end

  describe "#kill_line" do
    it "kills text from the cursor to the end of the line" do
      buffer.lines = ["abcdef"]
      buffer.cursor_pos = { row: 0, col: 2 }

      killed = buffer.kill_line

      expect(buffer.lines).to eq(["ab"])
      expect(killed).to eq("cdef")
      expect(buffer.cursor_pos).to eq({ row: 0, col: 2 })
    end

    it "joins the next line when killing at end of line" do
      buffer.lines = %w[abc def]
      buffer.cursor_pos = { row: 0, col: 3 }

      killed = buffer.kill_line

      expect(buffer.lines).to eq(["abcdef"])
      expect(killed).to eq("\n")
      expect(buffer.cursor_pos).to eq({ row: 0, col: 3 })
    end

    it "kills a final newline at end of the last line" do
      buffer.load_text("abc\n")
      buffer.cursor_pos = { row: 0, col: 3 }

      killed = buffer.kill_line

      expect(buffer.to_s).to eq("abc")
      expect(killed).to eq("\n")
      buffer.undo
      expect(buffer.to_s).to eq("abc\n")
    end
  end

  describe "region edits" do
    it "extracts and deletes a UTF-8 region across CRLF lines as one undo step" do
      buffer.load_text("aαb\r\ncd")

      expect(buffer.region_text({ row: 0, col: 1 }, { row: 1, col: 1 })).to eq("αb\r\nc")
      buffer.delete_region({ row: 0, col: 1 }, { row: 1, col: 1 })

      expect(buffer.to_s).to eq("ad")
      expect(buffer.cursor_pos).to eq({ row: 0, col: 1 })
      expect(buffer.undo).to be(true)
      expect(buffer.to_s).to eq("aαb\r\ncd")
    end

    it "does not delete a region in a readonly buffer" do
      buffer.load_text("abc")
      buffer.readonly = true

      expect(buffer.delete_region({ row: 0, col: 0 }, { row: 0, col: 2 })).to be(false)
      expect(buffer.to_s).to eq("abc")
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
      buffer.kill_line

      expect(buffer.lines).to eq(%w[abc def])
      expect(buffer.cursor_pos).to eq({ row: 0, col: 1 })
      expect(observer).to have_received(:update).once
    end
  end

  describe "modified state" do
    it "tracks edits against the last saved text" do
      buffer = described_class.new
      expect(buffer.modified?).to be(false)

      buffer.insert_char("x")
      expect(buffer.modified?).to be(true)
      buffer.backspace
      expect(buffer.modified?).to be(false)
    end

    it "marks loaded text as saved" do
      buffer = described_class.new.load_text("loaded\n")

      expect(buffer.modified?).to be(false)
    end
  end

  describe "edit history" do
    it "undoes and redoes Unicode edits without losing saved state" do
      buffer.load_text("A\n")
      buffer.insert_char("界")

      expect(buffer.to_s).to eq("界A\n")
      expect(buffer.undo).to be(true)
      expect(buffer.to_s).to eq("A\n")
      expect(buffer.modified?).to be(false)
      expect(buffer.redo).to be(true)
      expect(buffer.to_s).to eq("界A\n")
      expect(buffer.modified?).to be(true)
    end

    it "restores line splits, joins, and line-ending metadata" do
      buffer.load_text("alpha\r\nbeta")
      buffer.cursor_pos = { row: 0, col: 2 }
      buffer.newline

      expect(buffer.to_s).to eq("al\r\npha\r\nbeta")
      buffer.undo
      expect(buffer.to_s).to eq("alpha\r\nbeta")
      expect(buffer.cursor_pos).to eq({ row: 0, col: 2 })
      buffer.redo
      expect(buffer.to_s).to eq("al\r\npha\r\nbeta")
    end

    it "undoes backspace, delete, and kill-line edits" do
      [
        ["abc", { row: 0, col: 1 }, :backspace, "bc"],
        ["abc", { row: 0, col: 1 }, :delete_char, "ac"],
        ["abc", { row: 0, col: 1 }, :kill_line, "a"]
      ].each do |text, cursor, operation, edited_text|
        buffer.load_text(text)
        buffer.cursor_pos = cursor
        buffer.public_send(operation)

        expect(buffer.to_s).to eq(edited_text)
        expect(buffer.undo).to be(true)
        expect(buffer.to_s).to eq(text)
        expect(buffer.redo).to be(true)
        expect(buffer.to_s).to eq(edited_text)
      end
    end

    it "records a multi-character paste as one undo step" do
      buffer.load_text("ab")
      buffer.cursor_pos = { row: 0, col: 1 }
      buffer.insert_text("Привет\nмир")

      expect(buffer.lines).to eq(%w[aПривет мирb])
      expect(buffer.to_s).to eq("aПривет\nмирb")
      expect(buffer.cursor_pos).to eq({ row: 1, col: 3 })
      expect(buffer.undo).to be(true)
      expect(buffer.to_s).to eq("ab")
      expect(buffer.redo).to be(true)
      expect(buffer.to_s).to eq("aПривет\nмирb")
    end

    it "places the cursor after pasted text inserted in the middle of a line" do
      buffer.load_text("beforeafter")
      buffer.cursor_pos = { row: 0, col: 6 }

      buffer.insert_text("X\nY")

      expect(buffer.to_s).to eq("beforeX\nYafter")
      expect(buffer.cursor_pos).to eq({ row: 1, col: 1 })

      buffer.load_text("beforeafter")
      buffer.cursor_pos = { row: 0, col: 6 }
      buffer.insert_text("XYZ")
      expect(buffer.cursor_pos).to eq({ row: 0, col: 9 })
    end

    it "joins consecutive line kills into one kill-ring item" do
      buffer.load_text("abc\ndef")
      first_kill = buffer.kill_line
      second_kill = buffer.kill_line

      expect(buffer.to_s).to eq("def")
      expect(first_kill).to eq("abc")
      expect(second_kill).to eq("\n")
    end

    it "groups multiple edits into one undo step and clears redo after a new edit" do
      buffer.with_undo_group do
        buffer.insert_char("a")
        buffer.insert_char("b")
      end

      expect(buffer.undo).to be(true)
      expect(buffer.to_s).to eq("")
      expect(buffer.redo).to be(true)
      expect(buffer.to_s).to eq("ab")
      buffer.undo
      buffer.insert_char("c")
      expect(buffer.redo).to be(false)
      expect(buffer.to_s).to eq("c")
    end

    it "groups consecutive typed characters and starts a new group after movement" do
      buffer.insert_char("a")
      buffer.insert_char("b")

      expect(buffer.undo).to be(true)
      expect(buffer.to_s).to eq("")
      expect(buffer.redo).to be(true)
      expect(buffer.to_s).to eq("ab")

      buffer.move_cursor_left
      buffer.insert_char("x")
      expect(buffer.to_s).to eq("axb")
      expect(buffer.undo).to be(true)
      expect(buffer.to_s).to eq("ab")
      expect(buffer.undo).to be(true)
      expect(buffer.to_s).to eq("")
    end

    it "does not mutate readonly buffers" do
      buffer.insert_char("a")
      buffer.readonly = true

      expect(buffer.undo).to be(false)
      expect(buffer.redo).to be(false)
      expect(buffer.to_s).to eq("a")
    end
  end
end
# rubocop:enable Metrics/BlockLength
