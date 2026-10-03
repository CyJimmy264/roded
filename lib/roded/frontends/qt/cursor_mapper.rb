module Roded
  module Frontends
    # Maps core character columns to Qt's visual character-movement steps.
    # TODO(qt): HACK — qt 0.1.9 omits QTextEdit#textCursor/#setTextCursor.
    # Workaround: move across Qt grapheme boundaries; points inside a grapheme
    # map to its preceding caret boundary. Expose text-cursor access and set the
    # exact UTF-16 position in qt to remove this limitation.
    class QtCursorMapper
      # TODO(qt): HACK — qt 0.1.9 omits QTextCursor::MoveOperation enum names.
      # Replace these public Qt enum values when the binding exposes them.
      MOVE_START = 1
      MOVE_DOWN = 12
      MOVE_RIGHT = 19

      def self.place(editor, snapshot, text)
        point = snapshot.fetch(:point)
        row = snapshot.fetch(:row, point[:row])
        column = snapshot.fetch(:col, point[:col])
        line = text.split("\n", -1)[row].to_s
        editor.move_cursor(MOVE_START)
        row.times { editor.move_cursor(MOVE_DOWN) }
        grapheme_column(line, column).times { editor.move_cursor(MOVE_RIGHT) }
        editor.ensure_cursor_visible
      end

      def self.grapheme_column(line, character_column)
        target = character_column.clamp(0, line.length)
        consumed = 0
        graphemes = 0
        line.scan(/\X/) do |cluster|
          break if consumed + cluster.length > target

          consumed += cluster.length
          graphemes += 1
        end
        graphemes
      end
    end
  end
end
