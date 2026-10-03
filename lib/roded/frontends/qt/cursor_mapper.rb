module Roded
  module Frontends
    # Maps core character positions to offsets in Qt's UTF-16 text document.
    class QtCursorMapper
      def self.place(editor, snapshot, text)
        cursor = editor.text_cursor
        cursor.set_position(utf16_offset(text, snapshot.fetch(:point)))
        editor.set_text_cursor(cursor)
        editor.ensure_cursor_visible
      end

      def self.utf16_offset(text, point)
        lines = text.split("\n", -1)
        row = point.fetch(:row).clamp(0, lines.length - 1)
        preceding_lines_offset(lines, row) + line_offset(lines.fetch(row), point.fetch(:col))
      end

      def self.preceding_lines_offset(lines, row)
        lines.first(row).sum { |line| utf16_length(expanded_line(line)) + 1 }
      end

      def self.line_offset(line, column)
        utf16_length(QtTabExpander.expand(line, 0, column.clamp(0, line.length)))
      end

      def self.expanded_line(line)
        QtTabExpander.expand(line, 0, line.length)
      end

      def self.utf16_length(text)
        text.encode(Encoding::UTF_16LE).bytesize / 2
      end
    end
  end
end
