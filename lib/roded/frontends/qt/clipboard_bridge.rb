module Roded
  module Frontends
    # Bridges core clipboard commands to Qt's system clipboard.
    class QtClipboardBridge
      def read_text
        QApplication.clipboard.text.to_s
      end

      def write_text(text)
        QApplication.clipboard.set_text(text.to_s)
      end

      def dispatch_key(key, payload, application:, source_id:)
        return :consume if handle_shortcut(key, payload, application:, source_id:)

        enqueue_key_event(key, payload, application, source_id) if key
        :consume
      end

      def paste_event(payload, source_id:)
        Event.new(
          :paste,
          { text: read_text, source_id:, window_id: payload[:window_id] }
        )
      end

      def handle_shortcut(key, payload, application:, source_id:)
        event_key = { "C-S-c" => "M-w", "C-S-x" => "C-w" }[key]
        return enqueue_key_event(event_key, payload, application, source_id) if event_key
        return unless key == "C-S-v"

        application.push_event(paste_event(payload, source_id:))
        :consume
      end

      private

      def enqueue_key_event(key, payload, application, source_id)
        application.push_event(
          Event.new(:key, { key:, source_id:, window_id: payload[:window_id] })
        )
        :consume
      end
    end
  end
end
