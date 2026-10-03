module Roded
  module Frontends
    # Converts native Qt callbacks into source-tagged core input events.
    class QtInputRouter
      def initialize(application, key_translator, clipboard, source_id)
        @application = application
        @key_translator = key_translator
        @clipboard = clipboard
        @source_id = source_id
        @wheel_remainder = 0
      end

      def connect(view)
        view.on_key_press { |payload| enqueue_key(payload) }
        view.on_close { close_requested }
        view.on_resize { |_payload| @application.push_event(Event.new(:resize, {})) }
        view.on_wheel { |payload| enqueue_wheel(payload) }
      end

      def enqueue_key(payload)
        key = @key_translator.translate(payload)
        @clipboard.dispatch_key(key, payload, application: @application, source_id: @source_id)
      end

      def enqueue_wheel(payload)
        amount = wheel_amount(payload)
        if amount.nonzero?
          @application.push_event(
            Event.new(:scroll_by, { amount:, source_id: @source_id, window_id: payload[:window_id] })
          )
        end
        :consume
      end

      private

      def close_requested
        @application.push_event(Event.new(:close_request, {}))
        :reject
      end

      def wheel_amount(payload)
        angle_delta = payload.fetch(:angle_delta_y, 0).to_i
        return (-payload.fetch(:pixel_delta_y, 0).to_i / 40.0).round if angle_delta.zero?

        total_delta = @wheel_remainder + angle_delta
        notches = (total_delta / 120.0).truncate
        @wheel_remainder = total_delta - (notches * 120)
        -notches * 3
      end
    end
  end
end
