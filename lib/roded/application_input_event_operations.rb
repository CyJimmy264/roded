module Roded
  # Dispatches frontend input while keeping view and buffer cursor state aligned.
  module ApplicationInputEventOperations
    def handle_event(event)
      return handle_repl_api_event(event) if event.type == :repl_api_call
      return append_ruby_repl_result(event.payload) if event.type == :repl_result
      return handle_system_event(event) if system_event?(event)

      process_frontend_input(event)
    ensure
      @active_source_id = nil
    end

    private

    def system_event?(event)
      Application::SYSTEM_EVENTS.include?(event.type) || event.type == :close_request
    end

    def handle_system_event(event)
      event.type == :close_request ? request_quit : request_quit(force: true)
    end

    def process_frontend_input(event)
      logger.debug("handle_event: #{event.type}")
      logger.debug("handle_event: focus: #{@focus}")
      activate_target_window(event)
      window_before = @current_window
      buffer_before = current_buffer
      sync_buffer_cursor_to_window(window_before, buffer_before)
      @active_source_id = event.payload.fetch(:source_id, :default)
      dispatch_routed_input(event)
      sync_window_cursor_to_buffer(window_before, buffer_before)
      broadcast_command(Command.new(:render, {})) if windows.length > 1
    end

    def activate_target_window(event)
      target = windows.find { |window| window.object_id == event.payload[:window_id] }
      activate_window(target) if target && !target.equal?(@current_window)
    end

    def sync_buffer_cursor_to_window(window, buffer)
      buffer.cursor_pos = window.point if window && buffer
    end

    def dispatch_routed_input(event)
      routed_event = route_input_event(event)
      preserve_yank = %i[yank yank_pop].include?(routed_event&.type) || @focus == :minibuffer
      @last_yank = nil if routed_event && !preserve_yank
      @command_handler.handle(routed_event) if routed_event
    end

    def sync_window_cursor_to_buffer(window, buffer)
      return unless window && buffer
      return unless window.equal?(@current_window) && buffer.equal?(current_buffer)

      window.point = buffer.cursor_pos
    end
  end
end
