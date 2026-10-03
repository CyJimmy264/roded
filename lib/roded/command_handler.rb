module Roded
  # Routes normalized editor events to their core operations.
  class CommandHandler
    def initialize(editor)
      @editor = editor
    end

    def handle(event)
      @editor.kill_ring.break_sequence unless %i[kill_line kill_region].include?(event.type)
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
      when :move_word_forward
        @editor.current_buffer&.move_cursor_word_forward
        @editor.broadcast_command(Command.new(:render, {}))
      when :move_word_backward
        @editor.current_buffer&.move_cursor_word_backward
        @editor.broadcast_command(Command.new(:render, {}))
      when :document_start
        @editor.current_buffer&.move_cursor_document_start
        @editor.broadcast_command(Command.new(:render, {}))
      when :document_end
        @editor.current_buffer&.move_cursor_document_end
        @editor.broadcast_command(Command.new(:render, {}))
      when :page_down
        @editor.current_buffer&.move_cursor_page_down(@editor.page_size)
        @editor.broadcast_command(Command.new(:render, {}))
      when :page_up
        @editor.current_buffer&.move_cursor_page_up(@editor.page_size)
        @editor.broadcast_command(Command.new(:render, {}))
      when :scroll_line_up
        @editor.scroll_viewport(-1)
      when :scroll_line_down
        @editor.scroll_viewport(1)
      when :scroll_page_up
        @editor.scroll_viewport(-@editor.page_size)
      when :scroll_page_down
        @editor.scroll_viewport(@editor.page_size)
      when :line_start
        @editor.current_buffer&.move_cursor_line_start
        @editor.broadcast_command(Command.new(:render, {}))
      when :line_end
        @editor.current_buffer&.move_cursor_line_end
        @editor.broadcast_command(Command.new(:render, {}))
      when :kill_line
        @editor.current_buffer&.kill_line(@editor.kill_ring)
        @editor.broadcast_command(Command.new(:render, {}))
      when :set_mark
        @editor.set_mark
      when :kill_region
        @editor.kill_region
      when :copy_region
        @editor.copy_region
      when :yank
        @editor.yank
      when :yank_pop
        @editor.start_minibuffer(:kill_ring, "M-y ")
      when :line_search
        @editor.start_minibuffer(:line_search, "Find line: ")
      when :goto_line
        @editor.start_minibuffer(:goto_line, "Goto line: ")
      when :query_replace
        @editor.begin_query_replace
      when :project_files
        @editor.start_minibuffer(:open, "Project file: ")
      when :ruby_repl
        @editor.open_ruby_repl
      when :repl_evaluate
        @editor.evaluate_ruby_repl
      when :repl_interrupt
        @editor.interrupt_ruby_repl
      when :repl_history_previous
        @editor.cycle_ruby_repl_history(-1)
      when :repl_history_next
        @editor.cycle_ruby_repl_history(1)
      when :shrink_window_horizontally
        @editor.resize_window(-0.05)
      when :enlarge_window_horizontally
        @editor.resize_window(0.05)
      when :save_buffer
        @editor.execute_command("save")
      when :save_as_buffer
        @editor.execute_command("save-as")
      when :open_file
        @editor.execute_command("open")
      when :switch_buffer
        @editor.execute_command("switch-buffer")
      when :previous_buffer
        @editor.execute_command("previous-buffer")
      when :next_buffer
        @editor.execute_command("next-buffer")
      when :kill_buffer
        @editor.execute_command("kill-buffer")
      when :split_horizontal
        @editor.split_window(:horizontal)
      when :split_vertical
        @editor.split_window(:vertical)
      when :other_window
        @editor.other_window
      when :delete_window
        @editor.delete_window
      when :delete_other_windows
        @editor.delete_other_windows
      when :undo
        @editor.execute_command("undo")
      when :redo
        @editor.execute_command("redo")
      when :render
        @editor.broadcast_command(Command.new(:render, {}))
      when :quit
        @editor.execute_command("quit")
      when :request_quit
        @editor.execute_command("quit")
      when :custom_command
        @editor.execute_command(event.payload.fetch(:name))
      when :start_command
        @editor.start_minibuffer(:command, "M-x ")
      when :describe_bindings
        @editor.describe_bindings
      when :cancel
        @editor.broadcast_command(Command.new(:render, {}))
      when :backspace
        @editor.current_buffer&.backspace
      when :delete
        @editor.current_buffer&.delete_char
      when :enter
        @editor.current_buffer&.newline
      when :indent
        @editor.indent
      when :insert_char
        @editor.current_buffer&.insert_char(event.payload[:char])
      when :paste
        @editor.current_buffer&.insert_text(event.payload[:text])
      when :noop
        # nothing
      else
        # ignore unknown events for now
      end
    end

    def handle_minibuffer_event(event)
      case event.type
      when :move_down, :move_up
        @editor.move_picker(event.type == :move_down ? 1 : -1)
      when :move_left
        @editor.minibuffer.move_left
        @editor.render_minibuffer
      when :move_right
        @editor.minibuffer.move_right
        @editor.render_minibuffer
      when :backspace
        @editor.minibuffer.backspace
        @editor.render_minibuffer
        @editor.refresh_picker
      when :delete
        @editor.minibuffer.delete_char
        @editor.render_minibuffer
        @editor.refresh_picker
      when :insert_char
        @editor.minibuffer.insert_char(event.payload[:char])
        @editor.render_minibuffer
        @editor.refresh_picker
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
