module Roded
  module Frontends
    # Maps horizontal pixel offsets without rescanning the document for each column.
    module QtHorizontalCursorGeometry
      def left_column_at_viewport(editor, text, snapshot)
        row = snapshot.fetch(:point).fetch(:row)
        line = (snapshot[:lines] || lines_for(text)).fetch(row)
        column_at_line_offset(editor, line, editor.horizontal_scroll_bar.value)
      end

      def horizontal_offset(editor, text, row, column, snapshot = nil)
        lines = snapshot&.[](:lines) || lines_for(text)
        line = lines.fetch(row.to_i.clamp(0, lines.length - 1))
        line_horizontal_offset(editor, line, column)
      end

      def line_horizontal_offset(editor, line, column)
        prefix = QtTabExpander.expand(line, 0, column.to_i.clamp(0, line.length))
        editor.font_metrics.horizontal_advance(prefix, utf16_length(prefix))
      end

      def horizontal_origin_visible?(editor, text, snapshot, origin)
        point = snapshot.fetch(:point)
        row = point.fetch(:row)
        line = (snapshot[:lines] || lines_for(text)).fetch(row)
        point_offset = line_horizontal_offset(editor, line, point.fetch(:col))
        origin_offset = line_horizontal_offset(editor, line, origin)
        delta = point_offset - origin_offset
        delta.between?(0, editor.viewport.width)
      end

      def column_at_horizontal_offset(editor, text, row, offset, snapshot = nil)
        lines = snapshot&.[](:lines) || lines_for(text)
        line = lines.fetch(row.to_i.clamp(0, lines.length - 1))
        column_at_line_offset(editor, line, offset)
      end

      def column_at_line_offset(editor, line, offset)
        lower_bound = (0..line.length).bsearch { |column| line_horizontal_offset(editor, line, column) >= offset }
        return line.length unless lower_bound

        closest_column(editor, line, lower_bound, offset.to_i)
      end

      def closest_column(editor, line, lower_bound, offset)
        previous = [lower_bound - 1, 0].max
        [previous, lower_bound].min_by do |column|
          (line_horizontal_offset(editor, line, column) - offset.to_i).abs
        end
      end
    end
  end
end
