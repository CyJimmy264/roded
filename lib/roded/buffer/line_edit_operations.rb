module Roded
  # Implements line splitting and kill-to-line-end edits.
  module BufferLineEditOperations
    def kill_line(at:)
      return if readonly

      row, column = normalize_buffer_position(at).values_at(:row, :col)
      line = @lines[row]
      return kill_line_text(line, row, column) if column < line.length

      join_next_line_for_kill(row) if row < @lines.length - 1
    end

    def newline(at:)
      return if readonly

      row, column = normalize_buffer_position(at).values_at(:row, :col)
      first = { row:, col: column }
      record_edit(row, 1, 2, change: edit_change(first, first, { row: row + 1, col: 0 })) do
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
      first = { row:, col: column }
      change = edit_change(first, { row:, col: line.length }, first)
      record_edit(row, 1, 1, change:) { @lines[row] = line[0...column] }
      killed
    end

    def join_next_line_for_kill(row)
      join_next_line(row)
      "\n"
    end
  end
end
