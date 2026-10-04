module Roded
  module Frontends
    # Applies queued widget updates on the Qt GUI thread.
    class QtUiDispatcher
      COALESCED_ACTION_GROUPS = [
        %i[render layout],
        %i[refresh],
        %i[picker],
        %i[minibuffer minibuffer_clear]
      ].freeze
      ACTION_ROUTES = {
        render: %i[view render],
        layout: %i[view render_layout],
        refresh: %i[view refresh],
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
        @queue = []
        @queue_mutex = Mutex.new
        @timer = QTimer.new
        @timer.set_interval(12)
        @timer.connect("timeout") { |_payload| drain }
      end

      def post(action, payload = nil)
        @queue_mutex.synchronize do
          group = coalesced_action_group(action)
          @queue.reject! { |queued_action, _queued_payload| group&.include?(queued_action) }
          @queue << [action, payload]
        end
      end

      def start
        @timer.start
      end

      def stop
        @timer.stop
      end

      private

      def drain
        actions = @queue_mutex.synchronize { @queue.shift(@queue.length) }
        actions.each { |action, payload| apply(action, payload) }
      end

      def coalesced_action_group(action)
        COALESCED_ACTION_GROUPS.find { |group| group.include?(action) }
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
        stop
        @view.close
        @application.quit
      end
    end
  end
end
