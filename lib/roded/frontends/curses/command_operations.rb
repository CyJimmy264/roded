module Roded
  module Frontends
    # Routes UI commands to the curses window and echo-area operations.
    module CursesCommandOperations
      COMMAND_HANDLERS = {
        render: :render_command,
        minibuffer_render: :show_minibuffer,
        picker_render: :show_picker,
        minibuffer_clear: :clear_minibuffer,
        quit: :wake_getch
      }.freeze

      def handle_command(command)
        logger.debug("handle_command: #{command.type}")
        return if command.type == :move_cursor

        handler = COMMAND_HANDLERS[command.type]
        send(handler, command.payload) if handler
      end

      def display_message(message)
        status_row = @screen.maxy - 1
        @screen.setpos(status_row, 0)
        @screen.clrtoeol
        @screen.addstr(CursesTextGeometry.clip(message, @screen.maxx))
        @screen.refresh
      end

      private

      def render_command(payload)
        snapshot = payload[:editor_snapshot]
        snapshot ? render_layout(snapshot) : redraw
      end

      def show_minibuffer(payload)
        @minibuffer_state = payload
        render_minibuffer_overlay
      end

      def show_picker(payload)
        @picker_state = payload
        render_picker_overlay
      end

      def clear_minibuffer(_payload)
        @minibuffer_state = nil
        @picker_state = nil
        @minibuffer_view.clear
      end
    end
  end
end
