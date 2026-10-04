require_relative "horizontal_cursor_geometry"

module Roded
  module Frontends
    # Maps core character positions to offsets in Qt's UTF-16 text document.
    class QtCursorMapper
      extend QtHorizontalCursorGeometry

      def self.place(editor, snapshot, text, row_position: nil)
        cursor = editor.text_cursor
        point = snapshot.fetch(:point)
        lines = snapshot[:lines] || lines_for(text)
        row_position ? cursor.set_position(row_position) : move_to_row(cursor, point.fetch(:row))
        cursor.set_position(cursor.position + line_offset(lines.fetch(point[:row]), point.fetch(:col)))
        editor.set_text_cursor(cursor)
        editor.ensure_cursor_visible
      end

      def self.move_to_row(cursor, row)
        cursor.set_position(0)
        cursor.move_position(::Qt::QTextCursor::NextBlock, ::Qt::QTextCursor::MoveAnchor, row) if row.positive?
      end

      def self.position_at(editor, horizontal, vertical, text, snapshot = nil)
        point = ::Qt::QPoint.new
        point.set_x(horizontal.to_i)
        point.set_y(vertical.to_i)
        cursor = editor.cursor_for_position(point)
        core_position(text, cursor.position, snapshot)
      end

      def self.core_position(text, offset, snapshot = nil)
        lines = lines_for(text)
        row, line_offset = position_in_lines(lines, offset, snapshot)
        { row:, col: core_column(lines.fetch(row), line_offset) }
      end

      def self.position_in_lines(lines, offset, snapshot = nil)
        remaining = offset.to_i.clamp(0, document_length(lines, snapshot))
        lines.each_with_index do |line, row|
          expanded = expanded_line(line)
          line_length = rendered_line_length(line, expanded) + end_of_line_marker_length(line, row, snapshot)
          return [row, remaining] if remaining <= line_length

          remaining -= line_length + 1
        end
        [lines.length - 1, lines.last.length]
      end

      def self.document_length(lines, snapshot = nil)
        lines.each_with_index.sum do |line, row|
          rendered_line_length(line, expanded_line(line)) + end_of_line_marker_length(line, row, snapshot) + 1
        end - 1
      end

      def self.end_of_line_marker_length(line, row, snapshot)
        point = snapshot && snapshot[:point]
        point && point[:row] == row && point[:col] >= line.length && !line.empty? ? 1 : 0
      end

      def self.utf16_offset(text, point)
        lines = lines_for(text)
        row = point.fetch(:row).clamp(0, lines.length - 1)
        preceding_lines_offset(lines, row) + line_offset(lines.fetch(row), point.fetch(:col))
      end

      def self.lines_for(text)
        lines = text.split("\n", -1)
        lines.empty? ? [""] : lines
      end

      def self.preceding_lines_offset(lines, row)
        lines.first(row).sum { |line| rendered_line_length(line, expanded_line(line)) + 1 }
      end

      def self.rendered_line_length(line, expanded)
        utf16_length(expanded) + (line.empty? ? 1 : 0)
      end

      def self.line_offset(line, column)
        utf16_length(QtTabExpander.expand(line, 0, column.clamp(0, line.length)))
      end

      def self.core_column(line, line_offset)
        following = (0..line.length).bsearch { |column| line_offset(line, column) >= line_offset } || line.length
        [[following - 1, 0].max, following].min_by { |column| (line_offset(line, column) - line_offset).abs }
      end

      def self.expanded_line(line)
        QtTabExpander.expand(line, 0, line.length)
      end

      def self.utf16_length(text)
        text.ascii_only? ? text.length : text.encode(Encoding::UTF_16LE).bytesize / 2
      end
    end
  end
end
