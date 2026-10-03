module Roded
  module Frontends
    # Restores editor keyboard focus after Qt activates a top-level window.
    module QtWindowFocusOperations
      def focus_editor_after_show
        @editor&.set_focus
        @focus_timer ||= QTimer.new(@window)
        @focus_timer.set_single_shot(true)
        @focus_timer.connect("timeout") { |_payload| @editor&.set_focus }
        @focus_timer.set_interval(0)
        @focus_timer.start
      end
    end
  end
end
