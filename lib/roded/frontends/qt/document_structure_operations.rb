module Roded
  module Frontends
    # Updates a contiguous native block span while preserving unchanged prefix/suffix rows.
    module QtDocumentStructureOperations
      private

      def update_structure(snapshot, lines, renderer)
        first, old_last, new_last = changed_span(snapshot, lines)
        html = (first..new_last).map { |row| renderer.block_html(row) }
        replace_span(first, old_last, html.join, snapshot)
        @blocks[first..old_last] = html
        refresh_shifted_overlays(first, old_last, snapshot, lines, renderer)
      end

      def refresh_shifted_overlays(first, old_last, snapshot, lines, renderer)
        shifted = shifted_overlays(first, old_last, lines.length - @lines.length)
        update_rows((shifted + overlay_rows(snapshot)).uniq.sort.reverse, renderer)
      end

      def changed_span(snapshot, lines)
        first = 0
        first += 1 while first < [@lines.length, lines.length].min && same_content?(first, first, snapshot, lines)
        suffix = common_suffix(first, snapshot, lines)
        old_last = @lines.length - suffix - 1
        new_last = lines.length - suffix - 1
        return include_anchor(first, old_last, new_last) if old_last < first || new_last < first

        [first, old_last, new_last]
      end

      def include_anchor(first, old_last, new_last)
        first.positive? ? [first - 1, old_last, new_last] : [first, old_last + 1, new_last + 1]
      end

      def common_suffix(first, snapshot, lines)
        suffix = 0
        limit = [@lines.length, lines.length].min - first
        while suffix < limit && same_content?(@lines.length - suffix - 1, lines.length - suffix - 1, snapshot, lines)
          suffix += 1
        end
        suffix
      end

      def same_content?(old_row, new_row, snapshot, lines)
        @lines[old_row] == lines[new_row] && @snapshot[:tokens]&.[](old_row) == snapshot[:tokens]&.[](new_row)
      end

      def shifted_overlays(first, old_last, delta)
        overlay_rows(@snapshot).filter_map do |row|
          row < first ? row : (row + delta if row > old_last)
        end
      end

      def replace_span(first, last, html, snapshot)
        cursor = @editor.text_cursor
        cursor.begin_edit_block
        QtCursorMapper.move_to_row(cursor, first)
        cursor.move_position(::Qt::QTextCursor::NextBlock, ::Qt::QTextCursor::KeepAnchor, last - first) if last > first
        cursor.move_position(::Qt::QTextCursor::EndOfBlock, ::Qt::QTextCursor::KeepAnchor, 1)
        cursor.insert_html(html)
        set_row_format(cursor, first, snapshot)
      ensure
        cursor&.end_edit_block
      end
    end
  end
end
