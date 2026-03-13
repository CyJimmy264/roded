module Roded
  class CommandHandler
    def initialize(editor)
      @editor = editor
    end

    def handle(event)
      return handle_minibuffer_event(event) if @editor.focus == :minibuffer

      handle_buffer_event(event)
    end

    private

    def handle_buffer_event(event)
      case event.type
      when :move_down
        @editor.current_buffer&.move_cursor_down
        @editor.broadcast_command(Command.new(:move_cursor, { direction: :down }))
      when :move_up
        @editor.current_buffer&.move_cursor_up
        @editor.broadcast_command(Command.new(:move_cursor, { direction: :up }))
      when :move_left
        @editor.current_buffer&.move_cursor_left
        @editor.broadcast_command(Command.new(:move_cursor, { direction: :left }))
      when :move_right
        @editor.current_buffer&.move_cursor_right
        @editor.broadcast_command(Command.new(:move_cursor, { direction: :right }))
      when :page_down
        @editor.broadcast_command(Command.new(:scroll_page, { direction: :down }))
      when :page_up
        @editor.broadcast_command(Command.new(:scroll_page, { direction: :up }))
      when :line_start
        @editor.current_buffer&.move_cursor_line_start
        @editor.broadcast_command(Command.new(:render, {}))
      when :line_end
        @editor.current_buffer&.move_cursor_line_end
        @editor.broadcast_command(Command.new(:render, {}))
      when :kill_line
        @editor.current_buffer&.kill_line(@editor.kill_ring)
        @editor.broadcast_command(Command.new(:render, {}))
      when :save_buffer
        filename = @editor.current_buffer&.filename || "untitled"
        @editor.save_file(filename)
      when :render
        @editor.broadcast_command(Command.new(:render, {}))
      when :quit
        @editor.broadcast_command(Command.new(:quit, {}))
      when :start_command
        @editor.start_minibuffer(:command, "M-x ")
      when :cancel
        @editor.broadcast_command(Command.new(:render, {}))
      when :backspace
        @editor.current_buffer&.backspace
      when :delete
        @editor.current_buffer&.delete_char
      when :enter
        @editor.current_buffer&.newline
      when :insert_char
        @editor.current_buffer&.insert_char(event.payload[:char])
      when :noop
        # nothing
      else
        # ignore unknown events for now
      end
    end

    def handle_minibuffer_event(event)
      case event.type
      when :move_left
        @editor.minibuffer.move_left
        @editor.render_minibuffer
      when :move_right
        @editor.minibuffer.move_right
        @editor.render_minibuffer
      when :backspace
        @editor.minibuffer.backspace
        @editor.render_minibuffer
      when :delete
        @editor.minibuffer.delete_char
        @editor.render_minibuffer
      when :insert_char
        @editor.minibuffer.insert_char(event.payload[:char])
        @editor.render_minibuffer
      when :cancel
        @editor.cancel_minibuffer
      when :enter
        @editor.submit_minibuffer
      when :line_start
        @editor.minibuffer.move_to_start
        @editor.render_minibuffer
      when :line_end
        @editor.minibuffer.move_to_end
        @editor.render_minibuffer
      when :page_up
        @editor.minibuffer.move_to_start
        @editor.render_minibuffer
      when :page_down
        @editor.minibuffer.move_to_end
        @editor.render_minibuffer
      when :noop
        # nothing
      else
        # ignore unsupported events in minibuffer
      end
    end
  end
end
