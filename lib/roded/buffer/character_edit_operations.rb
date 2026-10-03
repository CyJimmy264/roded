module Roded
  # Implements character insertion, deletion, and multiline paste.
  module BufferCharacterEditOperations
    def insert_char(char, at:)
      return if readonly
      return if char.nil? || char.empty?

      position = normalize_buffer_position(at)
      row, column = position.values_at(:row, :col)
      record_edit(row, 1, 1, undo_group: :typing) { insert_character(row, column, char) }
    end

    def insert_text(text, at:)
      return if readonly
      return if text.nil? || text.empty?

      raise ArgumentError, "text must be valid UTF-8" unless text.encoding == Encoding::UTF_8 && text.valid_encoding?

      position = normalize_buffer_position(at)
      row, inserted_lines = paste_snapshot(text, position)
      record_edit(row, 1, inserted_lines.length) do
        @lines[row, 1] = inserted_lines
      end
    end

    def backspace(at:)
      return if readonly

      row, column = normalize_buffer_position(at).values_at(:row, :col)
      backspace_in_line(row, column) if column.positive?
      join_previous_line(row) if column.zero? && row.positive?
    end

    def delete_char(at:)
      return if readonly

      row, column = normalize_buffer_position(at).values_at(:row, :col)
      line = @lines[row]
      return delete_character(row, column) if column < line.length

      join_next_line(row) if row < @lines.length - 1
    end

    private

    def insert_character(row, column, char)
      @lines[row] = @lines[row].dup.insert(column, char)
    end

    def backspace_in_line(row, column)
      record_edit(row, 1, 1) do
        line = @lines[row].dup
        line.slice!(column - 1)
        @lines[row] = line
      end
    end

    def join_previous_line(row)
      row -= 1
      record_edit(row, 2, 1) do
        previous_line = @lines[row]
        @lines[row] = previous_line + @lines[row + 1]
        @lines.delete_at(row + 1)
      end
    end

    def delete_character(row, column)
      record_edit(row, 1, 1) do
        edited_line = @lines[row].dup
        edited_line.slice!(column)
        @lines[row] = edited_line
      end
    end

    def join_next_line(row)
      record_edit(row, 2, 1) do
        @lines[row] += @lines[row + 1]
        @lines.delete_at(row + 1)
      end
    end

    def paste_snapshot(text, position)
      row, column = position.values_at(:row, :col)
      segments = text.gsub("\r\n", "\n").split("\n", -1)
      before, after = paste_boundaries(row, column)
      [row, pasted_lines(segments, before, after)]
    end

    def paste_boundaries(row, column)
      line = @lines[row]
      [line[0...column], line[column..] || ""]
    end

    def pasted_lines(segments, before, after)
      segments.each_with_index.map do |segment, index|
        paste_line(segment, index, segments.length, before, after)
      end
    end

    def paste_line(segment, index, count, before, after)
      prefix = index.zero? ? before : ""
      suffix = index == count - 1 ? after : ""
      prefix + segment + suffix
    end
  end
end
