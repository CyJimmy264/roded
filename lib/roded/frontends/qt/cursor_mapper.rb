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

      def self.position_at(editor, horizontal, vertical, text, snapshot = nil)
        point = ::Qt::QPoint.new
        point.set_x(horizontal.to_i)
        point.set_y(vertical.to_i)
        cursor = editor.cursor_for_position(point)
        core_position(text, cursor.position, snapshot)
      end

      def self.left_column_at_viewport(editor, text, snapshot)
        row = snapshot.fetch(:point).fetch(:row)
        column_at_horizontal_offset(editor, text, row, editor.horizontal_scroll_bar.value)
      end

      def self.horizontal_offset(editor, text, row, column)
        lines = lines_for(text)
        line = lines.fetch(row.to_i.clamp(0, lines.length - 1))
        prefix = QtTabExpander.expand(line, 0, column.to_i.clamp(0, line.length))
        editor.font_metrics.horizontal_advance(prefix, utf16_length(prefix))
      end

      def self.horizontal_origin_visible?(editor, text, snapshot, origin)
        point = snapshot.fetch(:point)
        row = point.fetch(:row)
        point_offset = horizontal_offset(editor, text, row, point.fetch(:col))
        origin_offset = horizontal_offset(editor, text, row, origin)
        delta = point_offset - origin_offset
        delta.between?(0, editor.viewport.width)
      end

      def self.column_at_horizontal_offset(editor, text, row, offset)
        lines = lines_for(text)
        line = lines.fetch(row.to_i.clamp(0, lines.length - 1))
        lower_bound = lower_bound_column(editor, text, row, line.length, offset.to_i)
        return line.length unless lower_bound

        closest_column(editor, text, row, lower_bound, offset.to_i)
      end

      def self.lower_bound_column(editor, text, row, length, offset)
        (0..length).bsearch { |column| horizontal_offset(editor, text, row, column) >= offset }
      end

      def self.closest_column(editor, text, row, lower_bound, offset)
        previous = [lower_bound - 1, 0].max
        [previous, lower_bound].min_by do |column|
          (horizontal_offset(editor, text, row, column) - offset.to_i).abs
        end
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
        (0..line.length).min_by do |column|
          (line_offset(line, column) - line_offset).abs
        end
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
