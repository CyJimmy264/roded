module Roded
  module Frontends
    # Presents shared editor state through Qt widgets without owning document text.
    class QtEditorWindow
      # TODO(qt): HACK — qt 0.1.9 omits QTextCursor::MoveOperation enum names.
      # Workaround: use Qt's public integer values to place the read-only view cursor.
      # Extend the binding to expose this enum, then replace these values with named constants.
      MOVE_START = 1
      MOVE_DOWN = 12
      MOVE_RIGHT = 19

      attr_reader :window, :editor

      def initialize
        @window = QWidget.new
        @window.set_window_title("Roded")
        @editor = QPlainTextEdit.new(@window)
        @editor.set_read_only(true)
        @modeline = QLabel.new(@window)
        @minibuffer = QLabel.new(@window)
        build_layout
        set_theme
      end

      def on_key_press(&)
        @editor.on(:key_press, &)
      end

      def on_close(&)
        @window.on(:close, &)
      end

      def on_resize(&)
        @window.on(:resize, &)
      end

      def show
        @window.resize(960, 640)
        @window.show
        @editor.set_focus
      end

      def render(snapshot)
        @editor.set_plain_text(snapshot.fetch(:text))
        place_cursor(snapshot.fetch(:row), snapshot.fetch(:col))
        @modeline.set_text(snapshot.fetch(:modeline))
      end

      def render_minibuffer(payload)
        prompt = payload[:prompt].to_s
        text = payload[:text].to_s
        @minibuffer.set_text("#{prompt}#{text}")
      end

      def clear_minibuffer
        @minibuffer.clear
      end

      def display_message(message)
        @minibuffer.set_text(message.to_s)
      end

      def close
        @window.hide
      end

      private

      def build_layout
        layout = QVBoxLayout.new(@window)
        layout.add_widget(@editor)
        layout.add_widget(@modeline)
        layout.add_widget(@minibuffer)
      end

      def set_theme
        @window.set_style_sheet(
          "QWidget { background: #292b34; color: #bbc2cf; } " \
          "QPlainTextEdit { background: #282c34; color: #bbc2cf; border: 0; " \
          "selection-background-color: #3e4451; } QLabel { padding: 4px; }"
        )
      end

      def place_cursor(row, col)
        @editor.move_cursor(MOVE_START)
        row.times { @editor.move_cursor(MOVE_DOWN) }
        col.times { @editor.move_cursor(MOVE_RIGHT) }
        @editor.ensure_cursor_visible
      end
    end
  end
end
