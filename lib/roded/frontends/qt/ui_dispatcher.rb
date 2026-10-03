module Roded
  module Frontends
    # Applies queued widget updates on the Qt GUI thread.
    class QtUiDispatcher
      def initialize(view, application)
        @view = view
        @application = application
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
        case action
        when :render then @view.render(payload)
        when :layout then @view.render_layout(payload)
        when :message then @view.display_message(payload)
        when :minibuffer then @view.render_minibuffer(payload)
        when :minibuffer_clear then @view.clear_minibuffer
        when :quit then quit
        end
      end

      def quit
        @view.close
        @application.quit
      end
    end
  end
end
