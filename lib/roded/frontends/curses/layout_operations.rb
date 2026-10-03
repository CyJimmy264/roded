module Roded
  module Frontends
    # Renders editor-window rectangles, text rows, modelines and the active cursor.
    module CursesLayoutOperations
      private

      def render_layout(snapshot)
        return if CursesCursorRedraw.new(self).call(@layout_snapshot, snapshot)

        @layout_snapshot = snapshot
        @screen.clear
        draw_layout_windows(snapshot)
        render_overlays
        @screen.refresh
      end

      def draw_layout_windows(snapshot)
        rectangles = layout_rectangles(snapshot[:tree], 0, 0, @screen.maxx, editor_area_height)
        records = snapshot[:windows].to_h { |item| [item[:id], item] }
        rectangles.each { |rectangle| draw_window(records[rectangle.window_id], rectangle) }
      end

      def layout_rectangles(tree, left, top, width, height)
        return rectangle_for_window(tree, left, top, width, height) if tree[:window_id]

        if tree[:direction] == :vertical
          split_columns(tree, left, top, width, height)
        else
          split_rows(tree, left, top, width, height)
        end
      end

      def rectangle_for_window(tree, left, top, width, height)
        [CursesRenderContext::Rectangle.new(window_id: tree[:window_id], left:, top:, width:, height:)]
      end

      def split_columns(tree, left, top, width, height)
        first_width = split_extent(width, tree.fetch(:ratio, 0.5))
        layout_rectangles(tree[:first], left, top, first_width, height) +
          layout_rectangles(tree[:second], left + first_width, top, width - first_width, height)
      end

      def split_rows(tree, left, top, width, height)
        first_height = split_extent(height, tree.fetch(:ratio, 0.5))
        layout_rectangles(tree[:first], left, top, width, first_height) +
          layout_rectangles(tree[:second], left, top + first_height, width, height - first_height)
      end

      def split_extent(size, ratio)
        (size * ratio).round.clamp(1, [size - 1, 1].max)
      end

      def draw_window(item, rectangle)
        return unless item

        first_line, left_column = window_origin(item, rectangle.width, rectangle.height)
        draw_window_lines(item, first_line, left_column, rectangle)
        draw_modeline(item, rectangle.top + rectangle.height - 1, rectangle.left, rectangle.width)
        place_window_cursor(item, first_line, left_column, rectangle) if item[:active]
      end

      def window_origin(item, width, height)
        text_height = [height - 1, 0].max
        first_line = visible_origin(item[:point][:row], item[:top_line], text_height)
        active_line = item[:lines][item[:point][:row]].to_s
        left_column = CursesTextGeometry.horizontal_origin(
          active_line, item[:point][:col], item[:left_column], width
        )
        [first_line, left_column]
      end

      def draw_window_lines(item, first_line, left_column, rectangle)
        text_height = [rectangle.height - 1, 0].max
        item[:lines].slice(first_line, text_height).to_a.each_with_index do |line, index|
          context = CursesRenderContext::BufferLine.new(
            item:, line:, buffer_row: first_line + index, screen_row: rectangle.top + index,
            left: rectangle.left, width: rectangle.width, left_column:
          )
          draw_buffer_line(context)
        end
      end

      def place_window_cursor(item, first_line, left_column, rectangle)
        return unless rectangle.height.positive? && rectangle.width.positive?

        point = item[:point]
        cursor_row = window_cursor_row(point, first_line, rectangle)
        cursor_column = window_cursor_column(item, point, left_column, rectangle)
        @screen.setpos(cursor_row, cursor_column)
      end

      def window_cursor_row(point, first_line, rectangle)
        text_height = [rectangle.height - 1, 0].max
        last_row = [rectangle.top + text_height - 1, rectangle.top].max
        (rectangle.top + point[:row] - first_line).clamp(rectangle.top, last_row)
      end

      def window_cursor_column(item, point, left_column, rectangle)
        cursor_line = item[:lines][point[:row]].to_s
        cursor_column = CursesTextGeometry.column(cursor_line, point[:col]) -
                        CursesTextGeometry.column(cursor_line, left_column)
        (rectangle.left + cursor_column).clamp(rectangle.left, rectangle.left + rectangle.width - 1)
      end
    end
  end
end
