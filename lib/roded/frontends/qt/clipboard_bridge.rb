module Roded
  module Frontends
    # Uses Qt's widget clipboard actions as a transport for text owned by core.
    class QtClipboardBridge
      # TODO(qt): HACK — qt 0.1.9 exposes QApplication.clipboard as QObject
      # without QClipboard#text or #setText.
      # Workaround: use a transport-only QTextEdit document's native paste/copy slots
      # only to transfer plain text; never use that document as editor state.
      # Extend qt with QClipboard and replace these widget actions with its API.
      def initialize
        @transport = QTextEdit.new
        @transport.set_accept_rich_text(false)
      end

      def read_text
        return "" unless @transport.can_paste

        @transport.clear
        @transport.paste
        QApplication.process_events
        @transport.to_plain_text
      ensure
        @transport.clear
      end

      def write_text(text)
        @transport.set_plain_text(text.to_s)
        @transport.select_all
        @transport.copy
        @transport.clear
      end

      def paste_event(payload, source_id:)
        Event.new(
          :paste,
          { text: read_text, source_id:, window_id: payload[:window_id] }
        )
      end

      def enqueue_paste(key, payload, application:, source_id:)
        return unless key == "C-S-v"

        application.push_event(paste_event(payload, source_id:))
        :consume
      end
    end
  end
end
