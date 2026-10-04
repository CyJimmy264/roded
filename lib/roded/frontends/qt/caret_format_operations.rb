module Roded
  module Frontends
    # Keeps document characters intact when only the caret moves within a row.
    module QtCaretFormatOperations
      private

      def update_caret_formats?(snapshot, lines, renderer)
        return false unless caret_formats_only?(snapshot, lines)

        return true if @snapshot[:point] == snapshot[:point]

        row = snapshot[:point][:row]
        plain = snapshot.merge(point: { row: -1, col: 0 })
        source = QtEditorHtmlRenderer.new(snapshot[:text], plain)
        apply_cell_format(row, @snapshot[:point][:col], source)
        apply_cell_format(row, snapshot[:point][:col], renderer)
        @blocks[row] = renderer.block_html(row)
        true
      end

      def caret_formats_only?(snapshot, lines)
        return false unless unchanged_content?(snapshot, lines) && unselected_carets?(snapshot)

        previous = @snapshot[:point]
        current = snapshot[:point]
        previous[:row] == current[:row] &&
          [previous, current].all? { |point| point[:col] < lines.fetch(point[:row]).length }
      end

      def unchanged_content?(snapshot, lines)
        @snapshot && @lines.equal?(lines) && @snapshot[:tokens].equal?(snapshot[:tokens])
      end

      def unselected_carets?(snapshot)
        [@snapshot, snapshot].none? { |state| state[:mark] || state[:highlight] }
      end

      def apply_cell_format(row, column, renderer)
        template = caret_format_template
        template.set_html(renderer.character_html(row, column))
        source = template.text_cursor
        source.move_position(::Qt::QTextCursor::End, ::Qt::QTextCursor::MoveAnchor, 1)
        format = ::Qt::Native.qtext_cursor_char_format(source.handle)
        target = cell_cursor(row, column, renderer.lines.fetch(row))
        ::Qt::Native.qtext_cursor_set_char_format(target.handle, format)
      ensure
        ::Qt::Native.qtext_char_format_value_delete(format) if format
      end

      def cell_cursor(row, column, line)
        target = @editor.text_cursor
        origin = @index.position(row)
        target.set_position(origin + QtCursorMapper.line_offset(line, column))
        target.set_position(origin + QtCursorMapper.line_offset(line, column + 1), ::Qt::QTextCursor::KeepAnchor)
        target
      end

      def caret_format_template
        @caret_format_template ||= ::Qt::QTextEdit.new(@editor).tap do |template|
          template.set_font(@editor.font)
          template.hide
        end
      end
    end
  end
end
