module Roded
  # Mutates and navigates the editor's tree of views.
  module WindowLayoutOperations
    def add_window(window)
      if session.window_layout
        session.window_layout.split(current_window, window, :vertical)
      else
        session.window_layout = WindowLayout.new(window)
      end
      self.current_window = window if current_window.nil?
    end

    def windows
      session.window_layout ? session.window_layout.windows.freeze : [].freeze
    end

    def split_window(direction)
      return unless current_window

      window = current_window.copy
      session.window_layout.split(current_window, window, direction)
      self.current_window = window
      render_active_window
      window
    end

    def other_window
      return if windows.length < 2

      index = windows.index(current_window) || 0
      activate_window(windows[(index + 1) % windows.length])
    end

    def delete_window
      return display_message("Cannot delete the only window.") if windows.length < 2

      session.window_layout.remove(current_window)
      current_window.detach
      activate_window(windows.first)
    end

    def delete_other_windows
      return unless current_window

      windows.reject { |window| window.equal?(current_window) }.each(&:detach)
      session.window_layout.keep(current_window)
      render_active_window
    end

    def scroll_viewport(amount)
      return unless current_window

      update_viewport_origin(current_window.top_line + amount.to_i)
    end

    def resize_window(amount)
      return unless current_window && session.window_layout.resize_columns(current_window, amount)

      publish_ui_update(UIUpdate.new(:render, {}))
    end

    private

    def ensure_current_point_visible
      window = current_window
      return unless window

      visible_rows = page_size
      window.top_line = visible_origin(window, visible_rows)
    end

    def visible_origin(window, visible_rows)
      max_origin = [window.buffer.lines.length - visible_rows, 0].max
      origin = window.top_line.clamp(0, max_origin)
      row = window.point.fetch(:row)
      origin = row if row < origin
      origin = row - visible_rows + 1 if row >= origin + visible_rows
      origin.clamp(0, max_origin)
    end

    def update_viewport_origin(origin)
      previous_origin = current_window.top_line
      origin = clamp_viewport_origin(origin)
      return if origin == previous_origin

      current_window.top_line = origin
      move_point_with_viewport(origin - previous_origin)
      publish_ui_update(UIUpdate.new(:render, {}))
    end

    def clamp_viewport_origin(origin)
      last_origin = [current_buffer.lines.length - page_size, 0].max
      origin.clamp(0, last_origin)
    end

    def move_point_with_viewport(delta)
      point = current_window.point
      current_window.point = point.merge(row: point[:row] + delta)
    end
  end
end
