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
        @selection_anchor = nil
      end

      def connect(view)
        view.on_key_press { |payload| enqueue_key(payload) }
        view.on_close { close_requested }
        view.on_resize { |_payload| @application.push_event(Event.new(:resize, {})) }
        view.on_wheel { |payload| enqueue_wheel(payload) }
        view.on_mouse { |payload| enqueue_mouse(payload) }
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

      def enqueue_mouse(payload)
        case payload.fetch(:mouse_action)
        when :press then mouse_press(payload)
        when :move then mouse_move(payload)
        when :release then mouse_release(payload)
        else :ignore
        end
      end

      private

      def close_requested
        @application.push_event(Event.new(:close_request, {}))
        :reject
      end

      def mouse_press(payload)
        return :ignore unless payload.fetch(:button, 0).to_i == ::Qt::LeftButton

        @selection_anchor = payload.fetch(:position)
        push_mouse_selection(payload, @selection_anchor, nil)
      end

      def mouse_move(payload)
        return :ignore unless @selection_anchor && payload.fetch(:buttons, 0).to_i.anybits?(::Qt::LeftButton)

        push_mouse_selection(payload, payload.fetch(:position), @selection_anchor)
      end

      def mouse_release(payload)
        return :ignore unless payload.fetch(:button, 0).to_i == ::Qt::LeftButton && @selection_anchor

        anchor = @selection_anchor
        @selection_anchor = nil
        mark = anchor == payload.fetch(:position) ? nil : anchor
        push_mouse_selection(payload, payload.fetch(:position), mark)
      end

      def push_mouse_selection(payload, point, mark)
        @application.push_event(
          Event.new(
            :mouse_selection,
            { point:, mark:, source_id: @source_id, window_id: payload[:window_id] }
          )
        )
        :consume
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
