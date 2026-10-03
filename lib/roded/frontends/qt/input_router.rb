module Roded
  module Frontends
    # Converts native Qt callbacks into source-tagged core input events.
    class QtInputRouter
      def initialize(application, key_translator, clipboard, source_id)
        @application = application
        @key_translator = key_translator
        @clipboard = clipboard
        @source_id = source_id
      end

      def connect(view, &on_close)
        view.on_key_press { |payload| enqueue_key(payload) }
        view.on_close { close_requested(on_close) }
        view.on_resize { |_payload| @application.push_event(Event.new(:resize, {})) }
      end

      def enqueue_key(payload)
        key = @key_translator.translate(payload)
        @clipboard.dispatch_key(key, payload, application: @application, source_id: @source_id)
      end

      private

      def close_requested(on_close)
        # TODO(qt): HACK — qt 0.1.9 close callbacks cannot veto QWidget::close.
        # :consume accepts and closes; :ignore falls through to QWidget's default closeEvent.
        # QtCloseGuard reopens the retained view if core prompts or cancels the close.
        # Extend qt with a close-event veto result, then remove that reopen workaround.
        on_close.call
        @application.push_event(Event.new(:close_request, {}))
        :consume
      end
    end
  end
end
