module Roded
  module Frontends
    # Reopens a window if the core cancels a native close request.
    class QtCloseGuard
      def initialize(ui_dispatcher)
        @ui_dispatcher = ui_dispatcher
        @pending = false
      end

      def mark_pending
        @pending = true
      end

      def clear
        @pending = false
      end

      def reopen_if_pending
        return unless @pending

        @pending = false
        @ui_dispatcher.post(:reopen)
      end
    end
  end
end
