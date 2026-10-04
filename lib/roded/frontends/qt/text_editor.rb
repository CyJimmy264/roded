module Roded
  module Frontends
    # Plain-text layout avoids rich-document reflow while retaining inline formats.
    class QtTextEditor < ::Qt::QPlainTextEdit
      def initialize(parent = nil)
        super
        set_undo_redo_enabled(false)
      end

      def html=(html)
        document.set_html(html)
      end
      alias set_html html=

      def to_html = document.to_html

      def copy_document_from(source)
        source_cursor = source.text_cursor
        source_cursor.select(::Qt::QTextCursor::Document)
        fragment = ::Qt::Native.qtext_cursor_selection(source_cursor.handle)
        cursor = text_cursor
        cursor.begin_edit_block
        cursor.select(::Qt::QTextCursor::Document)
        # qt 0.2 has no QTextDocumentFragment wrapper; own the native value explicitly.
        ::Qt::Native.qtext_cursor_insert_fragment(cursor.handle, fragment)
      ensure
        cursor&.end_edit_block
        ::Qt::Native.qtext_document_fragment_value_delete(fragment) if fragment
      end
    end
  end
end
