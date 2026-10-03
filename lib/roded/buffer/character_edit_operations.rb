module Roded
  # Implements character insertion, deletion, and multiline paste.
  module BufferCharacterEditOperations
    def insert_char(char)
      return if readonly
      return if char.nil? || char.empty?

      row = @cursor_pos[:row]
      record_edit(row, 1, 1) { insert_character(row, char) }
    end

    def insert_text(text)
      return if readonly
      return if text.nil? || text.empty?

      raise ArgumentError, "text must be valid UTF-8" unless text.encoding == Encoding::UTF_8 && text.valid_encoding?

      row, inserted_lines, cursor_col = paste_snapshot(text)
      record_edit(row, 1, inserted_lines.length) do
        @lines[row, 1] = inserted_lines
        @cursor_pos = { row: row + inserted_lines.length - 1, col: cursor_col }
      end
    end

    def backspace
      return if readonly

      backspace_in_line if @cursor_pos[:col].positive?
      join_previous_line if @cursor_pos[:col].zero? && @cursor_pos[:row].positive?
    end

    def delete_char
      return if readonly

      line = @lines[@cursor_pos[:row]]
      return delete_character if @cursor_pos[:col] < line.length

      join_next_line if @cursor_pos[:row] < @lines.length - 1
    end

    private

    def insert_character(row, char)
      line = @lines[row]
      @lines[row] = line.dup.insert(@cursor_pos[:col], char)
      @cursor_pos[:col] = [@cursor_pos[:col] + char.length, line_at_cursor.length].min
    end

    def backspace_in_line
      row = @cursor_pos[:row]
      record_edit(row, 1, 1) do
        line = @lines[row].dup
        line.slice!(@cursor_pos[:col] - 1)
        @lines[row] = line
        @cursor_pos[:col] = [@cursor_pos[:col] - 1, 0].max
      end
    end

    def join_previous_line
      row = @cursor_pos[:row] - 1
      record_edit(row, 2, 1) do
        previous_line = @lines[row]
        @lines[row] = previous_line + @lines[row + 1]
        @lines.delete_at(row + 1)
        @cursor_pos = { row:, col: previous_line.length }
      end
    end

    def delete_character
      row = @cursor_pos[:row]
      record_edit(row, 1, 1) do
        edited_line = @lines[row].dup
        edited_line.slice!(@cursor_pos[:col])
        @lines[row] = edited_line
      end
    end

    def join_next_line
      row = @cursor_pos[:row]
      record_edit(row, 2, 1) do
        @lines[row] += @lines[row + 1]
        @lines.delete_at(row + 1)
      end
    end

    def paste_snapshot(text)
      row = @cursor_pos[:row]
      segments = text.gsub("\r\n", "\n").split("\n", -1)
      before, after = paste_boundaries
      [row, pasted_lines(segments, before, after), paste_cursor_column(segments, before)]
    end

    def paste_boundaries
      line = line_at_cursor
      [line[0...@cursor_pos[:col]], line[@cursor_pos[:col]..] || ""]
    end

    def pasted_lines(segments, before, after)
      segments.each_with_index.map do |segment, index|
        paste_line(segment, index, segments.length, before, after)
      end
    end

    def paste_cursor_column(segments, before)
      (segments.length == 1 ? before.length : 0) + segments.last.length
    end

    def paste_line(segment, index, count, before, after)
      prefix = index.zero? ? before : ""
      suffix = index == count - 1 ? after : ""
      prefix + segment + suffix
    end
  end
end
