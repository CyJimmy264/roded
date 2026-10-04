module Roded
  module Frontends
    # Maintains the single-buffer viewport used before a window layout exists.
    module CursesViewportOperations
      def draw_placeholder
        lines = ["Welcome Curses", "M-x for commands, C-x C-c to quit"]
        @screen.clear
        lines.first(@screen.maxy).each_with_index do |line, index|
          @screen.setpos(index, 0)
          @screen.addstr(CursesTextGeometry.clip(line, @screen.maxx))
        end
        @screen.setpos(0, 0)
        @screen.refresh
      end

      def scroll_viewport_up # rubocop:disable Naming/PredicateMethod -- this action changes the viewport
        return false unless @top.positive?

        @top -= 1
        redraw
        true
      end

      def scroll_viewport_down # rubocop:disable Naming/PredicateMethod -- this action changes the viewport
        return false unless @current_buffer
        return false if @top + @screen.maxy >= @current_buffer.lines.length

        @top += 1
        redraw
        true
      end

      def render(buffer = nil)
        @current_buffer = buffer if buffer
        @data_lines = @current_buffer&.lines || []
        @current_point ||= { row: 0, col: 0 }
        ensure_cursor_visible
        redraw
      end

      def page_size(window_id = nil)
        height = [@screen.maxy - 1, 1].max
        return [height - 1, 1].max unless @layout_snapshot && window_id

        rectangle = layout_rectangles(@layout_snapshot[:tree], 0, 0, @screen.maxx, height)
                    .find { |item| item.window_id == window_id }
        [rectangle ? rectangle.height - 1 : height - 1, 1].max
      end

      private

      def ensure_cursor_visible(_direction = nil)
        return unless @current_buffer

        row = @current_point.fetch(:row).clamp(0, @current_buffer.lines.length - 1)
        if row < @top
          @top = row
        elsif row >= @top + @screen.maxy
          @top = row - @screen.maxy + 1
        end
      end

      def redraw
        return unless @screen

        @screen.clear
        visible_lines = (@data_lines || [])[@top, @screen.maxy] || []
        visible_lines.each_with_index do |line, index|
          @screen.setpos(index, 0)
          @screen.addstr(CursesTextGeometry.clip(line, @screen.maxx))
        end
        place_cursor
        render_overlays
        @screen.refresh
      end

      def render_overlays
        render_minibuffer_overlay
        render_picker_overlay
      end

      def place_cursor
        return unless @current_buffer

        @screen.setpos(legacy_cursor_row, legacy_cursor_column)
      end

      def legacy_cursor_row
        row = @current_point.fetch(:row).clamp(0, @current_buffer.lines.length - 1)
        (row - @top).clamp(0, @screen.maxy - 1)
      end

      def legacy_cursor_column
        row = @current_point.fetch(:row).clamp(0, @current_buffer.lines.length - 1)
        line = @current_buffer.lines[row].to_s
        column = [@current_point.fetch(:col), line.length].min
        CursesTextGeometry.column(line, column).clamp(0, @screen.maxx - 1)
      end

      def visible_origin(point, origin, span)
        return point if point < origin
        return point - span + 1 if span.positive? && point >= origin + span

        origin
      end
    end
  end
end
