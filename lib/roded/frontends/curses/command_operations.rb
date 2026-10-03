module Roded
  module Frontends
    # Routes UI commands to the curses window and echo-area operations.
    module CursesCommandOperations
      COMMAND_HANDLERS = {
        render: :render_command,
        message: :show_message,
        focus: :apply_focus,
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
        previous_area_height = editor_area_height
        @picker_state = payload
        if @layout_snapshot && previous_area_height != editor_area_height
          render_layout(@layout_snapshot)
        else
          render_picker_overlay
          @screen.refresh
        end
      end

      def clear_minibuffer(_payload)
        @minibuffer_state = nil
        @picker_state = nil
        if @layout_snapshot
          render_layout(@layout_snapshot)
        else
          @minibuffer_view.clear
        end
      end

      def show_message(payload)
        display_message(payload.fetch(:text))
      end

      def apply_focus(payload)
        @focus = payload.fetch(:focus)
      end
    end
  end
end
