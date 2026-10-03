module Roded
  # Coordinates kill-line edits with the application-owned kill ring.
  module KillRingOperations
    def kill_line
      return unless current_buffer && current_window

      text = current_buffer.kill_line(at: current_window.point)
      return unless text

      kill_ring.push(text)
      publish_ui_update(UIUpdate.new(:render, {}))
    end
  end
end
