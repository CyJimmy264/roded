module Roded
  # Handles frontend and lifecycle events outside the normal command router.
  module ApplicationSpecialEventOperations
    SPECIAL_INPUT_EVENT_TYPES = %i[
      repl_api_call repl_result syntax_result mouse_selection horizontal_scroll resize
    ].freeze

    private

    def special_input_event?(event)
      SPECIAL_INPUT_EVENT_TYPES.include?(event.type) || system_event?(event)
    end

    def dispatch_special_input_event(event)
      case event.type
      when :repl_api_call then handle_repl_api_event(event)
      when :repl_result then append_ruby_repl_result(event.payload)
      when :syntax_result then handle_syntax_result(event.payload)
      when :mouse_selection then handle_mouse_selection(event)
      when :horizontal_scroll then handle_horizontal_scroll(event)
      when :resize then handle_resize_event
      else handle_system_event(event)
      end
    end

    def system_event?(event)
      Application::SYSTEM_EVENTS.include?(event.type) || event.type == :close_request
    end

    def handle_system_event(event)
      event.type == :close_request ? request_quit : request_quit(force: true)
    end
  end
end
