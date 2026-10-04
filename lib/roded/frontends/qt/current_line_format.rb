module Roded
  module Frontends
    # HTML insertion retains the destination paragraph format; replace it explicitly.
    class QtCurrentLineFormat
      def initialize(editor)
        @template = ::Qt::QTextEdit.new(editor)
        @template.hide
        @template.set_html('<p style="margin:0; padding:0; white-space:pre;">plain</p>' \
                           '<p style="margin:0; padding:0; white-space:pre; background-color:#343a46;">active</p>')
      end

      def apply(cursor, active:)
        source = @template.text_cursor
        QtCursorMapper.move_to_row(source, active ? 1 : 0)
        # qt 0.2 exposes these native operations but has no QTextBlockFormat Ruby wrapper.
        format = ::Qt::Native.qtext_cursor_block_format(source.handle)
        ::Qt::Native.qtext_cursor_set_block_format(cursor.handle, format)
      ensure
        ::Qt::Native.qtext_block_format_value_delete(format) if format
      end
    end
  end
end
