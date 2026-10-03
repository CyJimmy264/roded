module Roded
  # Implements line splitting and kill-to-line-end edits.
  module BufferLineEditOperations
    def kill_line(at:)
      return if readonly

      row, column = normalize_buffer_position(at).values_at(:row, :col)
      line = @lines[row]
      return kill_line_text(line, row, column) if column < line.length

      join_next_line_for_kill(line, row) if row < @lines.length - 1
    end

    def newline(at:)
      return if readonly

      row, column = normalize_buffer_position(at).values_at(:row, :col)
      record_edit(row, 1, 2) do
        line = @lines[row]
        before = line[0...column]
        after = line[column..] || ""
        @lines[row] = before
        @lines.insert(row + 1, after)
      end
    end

    private

    def kill_line_text(line, row, column)
      killed = line[column..]
      record_edit(row, 1, 1) { @lines[row] = line[0...column] }
      killed
    end

    def join_next_line_for_kill(line, row)
      record_edit(row, 2, 1) do
        @lines[row] = line + @lines[row + 1]
        @lines.delete_at(row + 1)
      end
      "\n"
    end
  end
end
