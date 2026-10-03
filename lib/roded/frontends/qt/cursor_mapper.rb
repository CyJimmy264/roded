module Roded
  module Frontends
    # Maps exact core character positions to Qt's UTF-16 caret positions.
    class QtCursorMapper
      # TODO(qt): HACK — qt 0.1.9 omits QTextEdit#textCursor/#setTextCursor.
      # Workaround: insert a unique private-use marker at the core character
      # boundary, find it through QTextEdit, and remove it before Qt can paint.
      # Expose text-cursor access and set UTF-16 offsets directly to remove this.
      # TODO(qt): HACK — qt 0.1.9 omits QTextCursor::MoveOperation enum names.
      # These public enum values remain only as a fallback if marker search fails.
      MOVE_START = 1
      MOVE_DOWN = 12
      MOVE_RIGHT = 19

      def self.marker_for(text)
        (0xE000..0xF8FF).each do |codepoint|
          marker = codepoint.chr(Encoding::UTF_8)
          return marker unless text.include?(marker)
        end

        marker = "\uE000"
        marker << "\uE000" while text.include?(marker)
        marker
      end

      def self.place(editor, snapshot, text)
        return if marker_placed?(editor, snapshot.fetch(:cursor_marker))

        place_by_grapheme(editor, snapshot, text)
      ensure
        editor.set_read_only(true)
      end

      def self.marker_placed?(editor, marker)
        editor.move_cursor(MOVE_START)
        return false unless editor.find(marker)

        editor.set_read_only(false)
        editor.insert_plain_text("")
        editor.ensure_cursor_visible
        true
      end

      def self.place_by_grapheme(editor, snapshot, text)
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
