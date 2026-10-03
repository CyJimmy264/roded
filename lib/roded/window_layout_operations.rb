module Roded
  # Mutates and navigates the editor's tree of views.
  module WindowLayoutOperations
    def add_window(window)
      if @window_layout
        @window_layout.split(@current_window, window, :vertical)
        @windows = @window_layout.windows
      else
        @window_layout = WindowLayout.new(window)
        @windows = [window]
      end
      @current_window = window if @current_window.nil?
    end

    def windows
      @window_layout ? @window_layout.windows.freeze : [].freeze
    end

    def split_window(direction)
      return unless @current_window

      window = @current_window.copy
      @window_layout.split(@current_window, window, direction)
      @windows = @window_layout.windows
      @current_window = window
      @current_buffer = window.buffer
      render_active_window
      window
    end

    def other_window
      return if windows.length < 2

      index = windows.index(@current_window) || 0
      activate_window(windows[(index + 1) % windows.length])
    end

    def delete_window
      return display_message("Cannot delete the only window.") if windows.length < 2

      removed = @current_window
      @window_layout.remove(removed)
      @windows = @window_layout.windows
      activate_window(@windows.first)
    end

    def delete_other_windows
      return unless @current_window

      @window_layout.keep(@current_window)
      @windows = [@current_window]
      render_active_window
    end

    def scroll_viewport(amount)
      return unless current_window

      update_viewport_origin(current_window.top_line + amount.to_i)
    end

    def resize_window(amount)
      return unless current_window && @window_layout.resize_columns(current_window, amount)

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
