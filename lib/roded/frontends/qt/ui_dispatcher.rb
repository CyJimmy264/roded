module Roded
  module Frontends
    # Applies queued widget updates on the Qt GUI thread.
    class QtUiDispatcher
      ACTION_ROUTES = {
        render: %i[view render],
        layout: %i[view render_layout],
        message: %i[view display_message],
        minibuffer: %i[view render_minibuffer],
        picker: %i[view render_picker],
        clipboard_write: %i[clipboard write_text],
        minibuffer_clear: %i[self clear_minibuffer],
        quit: %i[self quit]
      }.freeze

      def initialize(view, application, clipboard)
        @view = view
        @application = application
        @clipboard = clipboard
        @targets = { view: @view, clipboard: @clipboard, self: self }
        @queue = Queue.new
        @timer = QTimer.new
        @timer.set_interval(12)
        @timer.connect("timeout") { |_payload| drain }
      end

      def post(action, payload = nil)
        @queue << [action, payload]
      end

      def start
        @timer.start
      end

      private

      def drain
        apply(*@queue.pop(true)) until @queue.empty?
      rescue ThreadError
        nil
      end

      def apply(action, payload)
        route = ACTION_ROUTES[action]
        return unless route

        @targets.fetch(route.first).send(route.last, payload)
      end

      def clear_minibuffer(_payload)
        @view.clear_minibuffer
      end

      def quit(_payload)
        @view.close
        @application.quit
      end
    end
  end
end
