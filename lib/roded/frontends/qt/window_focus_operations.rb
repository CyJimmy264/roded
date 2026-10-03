module Roded
  module Frontends
    # Restores editor keyboard focus after Qt activates a top-level window.
    module QtWindowFocusOperations
      def focus_editor_after_show
        @editor&.set_focus
        @focus_timer ||= QTimer.new(@window)
        @focus_timer.set_single_shot(true)
        @focus_timer.connect("timeout") do |_payload|
          @window.activate_window
          @editor&.set_focus
        end
        @focus_timer.set_interval(100)
        @focus_timer.start
      end
    end
  end
end
