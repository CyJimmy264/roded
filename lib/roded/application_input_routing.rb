module Roded
  # Converts frontend key events into application commands.
  module ApplicationInputRouting
    private

    def route_input_event(event)
      return event unless event.type == :key

      routed = @command_router.route(event.payload[:key], source_id: @active_source_id)
      return unless routed
      return show_prefix_hint(routed) if routed.type == :prefix_pending
      return show_invalid_sequence(routed) if routed.payload[:invalid_sequence]

      routed
    end

    def show_prefix_hint(event)
      display_message("#{event.payload[:prefix]} …")
      nil
    end

    def show_invalid_sequence(event)
      display_message("Unknown key sequence: #{event.payload[:invalid_sequence]}")
      nil
    end
  end
end
