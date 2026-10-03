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
      activate_window(windows.first)
    end

    def delete_other_windows
      return unless current_window

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
      current_buffer.cursor_pos = current_window.point
    end
  end
end
