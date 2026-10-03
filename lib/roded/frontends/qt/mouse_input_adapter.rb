require_relative "cursor_mapper"

module Roded
  module Frontends
    # Converts native editor mouse coordinates into core text positions.
    class QtMouseInputAdapter
      EVENTS = {
        mouse_button_press: :press,
        mouse_move: :move,
        mouse_button_release: :release
      }.freeze

      def initialize(editor)
        @editor = editor
        @subscribed = false
      end

      def bind(window_id, callback)
        @window_id = window_id
        @callback = callback
        subscribe
      end

      attr_writer :text

      private

      def subscribe
        return if @subscribed || !@callback

        EVENTS.each do |event, action|
          @editor.on(event) { |payload| route(action, payload) }
        end
        @subscribed = true
      end

      def route(action, payload)
        return :ignore unless @text

        @editor.set_focus
        position = QtCursorMapper.position_at(
          @editor, payload.fetch(:x, 0), payload.fetch(:y, 0), @text
        )
        @callback.call(payload.merge(mouse_action: action, position:, window_id: @window_id))
      end
    end
  end
end
