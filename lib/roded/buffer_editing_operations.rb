module Roded
  # Implements undo, region, kill-ring, and clipboard-like editor commands.
  module BufferEditingOperations
    def undo
      changed = current_buffer&.undo
      broadcast_command(Command.new(:render, {})) if changed
      changed
    end

    def redo
      changed = current_buffer&.redo
      broadcast_command(Command.new(:render, {})) if changed
      changed
    end

    def set_mark
      return unless current_window

      current_window.mark = current_window.point
      broadcast_command(Command.new(:render, {}))
    end

    def copy_region
      region = active_region
      return display_message("No active region.") unless region

      kill_ring.break_sequence
      kill_ring.push(current_buffer.region_text(*region))
      display_message("Region copied.")
    end

    def kill_region
      region = active_region
      return display_message("No active region.") unless region

      text = current_buffer.region_text(*region)
      return unless current_buffer.delete_region(*region)

      kill_ring.push(text)
      current_window.mark = nil
      broadcast_command(Command.new(:render, {}))
    end

    def yank
      text = kill_ring.last
      return display_message("Kill ring is empty.") unless text

      start = current_window.point.dup
      current_buffer.insert_text(text)
      @last_yank = { buffer: current_buffer, start:, finish: current_buffer.cursor_pos, index: 0 }
      current_window.mark = nil
      broadcast_command(Command.new(:render, {}))
    end

    def yank_pop
      return display_message("No previous yank to replace.") unless previous_yank_for_current_buffer?
      return display_message("Kill ring has no other entries.") if kill_ring.items.length < 2

      replace_last_yank
      current_window.mark = nil
      broadcast_command(Command.new(:render, {}))
    end

    private

    def active_region
      return unless current_window&.mark

      [current_window.mark, current_window.point]
    end

    def previous_yank_for_current_buffer?
      @last_yank&.fetch(:buffer).equal?(current_buffer)
    end

    def replace_last_yank
      ring_index, text = next_yank
      current_buffer.with_undo_group do
        current_buffer.delete_region(@last_yank.fetch(:start), @last_yank.fetch(:finish))
        current_buffer.insert_text(text)
      end
      @last_yank[:finish] = current_buffer.cursor_pos
      @last_yank[:index] = ring_index
    end

    def next_yank
      ring_index = (@last_yank.fetch(:index) + 1) % kill_ring.items.length
      [ring_index, kill_ring.items.fetch(ring_index)]
    end
  end
end
