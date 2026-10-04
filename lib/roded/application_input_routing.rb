module Roded
  # Converts frontend key events into application commands.
  module ApplicationInputRouting
    private

    def route_input_event(event)
      routed = event.type == :key ? route_key_event(event) : command_from_input(event)
      return unless routed
      return show_prefix_hint(routed) if routed.type == :prefix_pending
      return show_invalid_sequence(routed) if routed.payload[:invalid_sequence]

      clear_prefix_hint
      routed
    end

    def route_key_event(event)
      @command_router.route(
        event.payload[:key], source_id: @active_source_id, view_id: event.payload[:window_id]
      )
    end

    def command_from_input(event)
      EditorCommand.new(event.type, event.payload, event.payload[:source_id], event.payload[:window_id])
    end

    def show_prefix_hint(event)
      (@prefix_hints ||= {})[@active_source_id] = event.payload[:prefix]
      display_message("#{event.payload[:prefix]} …")
      nil
    end

    def show_invalid_sequence(event)
      @prefix_hints&.delete(@active_source_id)
      display_message("Unknown key sequence: #{event.payload[:invalid_sequence]}")
      nil
    end

    def clear_prefix_hint
      return unless @prefix_hints&.delete(@active_source_id)

      hint = @prefix_hints.values.last
      display_message(hint ? "#{hint} …" : "")
    end
  end
end
