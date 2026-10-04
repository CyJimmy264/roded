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
        @running = false
        @wake_pending = false
        initialize_timer
      end

      def post(action, payload = nil)
        @queue_mutex.synchronize do
          group = coalesced_action_group(action)
          @queue.reject! { |queued_action, _queued_payload| group&.include?(queued_action) }
          @queue << [action, payload]
          request_wakeup
        end
      end

      def start
        @queue_mutex.synchronize do
          @running = true
          request_wakeup
        end
      end

      def stop
        @queue_mutex.synchronize do
          @running = false
          @wake_pending = false
        end
        @timer.stop
      end

      private

      def initialize_timer
        @timer = QTimer.new
        @timer.set_interval(0)
        @timer.set_single_shot(true)
        @timer.connect("timeout") { |_payload| dispatch_pending }
      end

      def request_wakeup
        return if !@running || @wake_pending || @queue.empty?

        @wake_pending = true
        # Queue the receiver's start slot; ordinary QTimer.start is GUI-thread-only.
        ::Qt::Native.qtimer_single_shot(@timer.handle, 0, @timer.handle, "1start()")
      end

      def dispatch_pending
        actions = @queue_mutex.synchronize do
          @wake_pending = false
          @running ? @queue.shift(@queue.length) : []
        end
        actions.each { |action, payload| apply(action, payload) }
      end

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
