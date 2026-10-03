module Roded
  # Implements line splitting and kill-to-line-end edits.
  module BufferLineEditOperations
    def kill_line
      return if readonly

      line = line_at_cursor
      return kill_line_text(line) if @cursor_pos[:col] < line.length

      join_next_line_for_kill(line) if @cursor_pos[:row] < @lines.length - 1
    end

    def newline
      return if readonly

      row = @cursor_pos[:row]
      record_edit(row, 1, 2) do
        line = @lines[row]
        before = line[0...@cursor_pos[:col]]
        after = line[@cursor_pos[:col]..] || ""
        @lines[row] = before
        @lines.insert(row + 1, after)
        @cursor_pos = { row: row + 1, col: 0 }
      end
    end

    private

    def kill_line_text(line)
      killed = line[@cursor_pos[:col]..]
      row = @cursor_pos[:row]
      record_edit(row, 1, 1) { @lines[row] = line[0...@cursor_pos[:col]] }
      killed
    end

    def join_next_line_for_kill(line)
      row = @cursor_pos[:row]
      record_edit(row, 2, 1) do
        @lines[row] = line + @lines[row + 1]
        @lines.delete_at(row + 1)
      end
      "\n"
    end
  end
end
