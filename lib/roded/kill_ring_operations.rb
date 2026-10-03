module Roded
  # Coordinates kill-line edits with the application-owned kill ring.
  module KillRingOperations
    def kill_line
      text = current_buffer&.kill_line
      return unless text

      kill_ring.push(text)
      broadcast_command(Command.new(:render, {}))
    end
  end
end
