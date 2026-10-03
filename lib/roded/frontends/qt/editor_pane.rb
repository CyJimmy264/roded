module Roded
  module Frontends
    # Renders one editor view and routes its key events to the core.
    class QtEditorPane
      MOVE_START = 1
      MOVE_DOWN = 12
      MOVE_RIGHT = 19

      attr_reader :container, :editor

      def initialize(parent)
        @container = QWidget.new(parent)
        layout = QVBoxLayout.new(@container)
        @editor = QPlainTextEdit.new(@container)
        @editor.set_read_only(true)
        @modeline = QLabel.new(@container)
        layout.add_widget(@editor)
        layout.add_widget(@modeline)
        @subscribed = false
      end

      def bind(window_id, callback)
        @window_id = window_id
        @key_callback = callback
        subscribe_keys
      end

      def render(snapshot)
        @editor.set_plain_text(snapshot.fetch(:text))
        place_cursor(snapshot.fetch(:row, snapshot.dig(:point, :row)),
                     snapshot.fetch(:col, snapshot.dig(:point, :col)))
        @modeline.set_text(snapshot[:modeline] || modeline_for(snapshot))
      end

      private

      def subscribe_keys
        return if @subscribed || !@key_callback

        @editor.on(:key_press) do |payload|
          @key_callback.call(payload.merge(window_id: @window_id))
        end
        @subscribed = true
      end

      def modeline_for(snapshot)
        point = snapshot.fetch(:point)
        active = snapshot[:active] ? "--" : "  "
        "#{active} Roded -- #{snapshot.fetch(:name)}  #{point[:row] + 1}:#{point[:col] + 1}"
      end

      def place_cursor(row, col)
        return unless row && col

        @editor.move_cursor(MOVE_START)
        row.times { @editor.move_cursor(MOVE_DOWN) }
        col.times { @editor.move_cursor(MOVE_RIGHT) }
        @editor.ensure_cursor_visible
      end
    end
  end
end
