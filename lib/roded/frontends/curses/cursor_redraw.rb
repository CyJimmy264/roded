module Roded
  module Frontends
    # Paints cursor-only layout updates without clearing the curses screen.
    class CursesCursorRedraw
      def initialize(frontend)
        @frontend = frontend
        @screen = frontend.instance_variable_get(:@screen)
      end

      def call(previous, snapshot)
        return false unless CursesCursorSnapshotComparison.call(previous, snapshot)

        context = cursor_context(previous, snapshot)
        return false unless context

        redraw_cursor_rows(context)
        modeline_row = context[:top] + context[:height] - 1
        @frontend.send(:draw_modeline, context[:item], modeline_row, context[:left], context[:width])
        place_cursor(context)
        @frontend.instance_variable_set(:@layout_snapshot, snapshot)
        @screen.refresh
        true
      end

      private

      def cursor_context(previous, snapshot)
        old_item = previous[:windows].find { |item| item[:id] == snapshot[:active_window_id] }
        item = snapshot[:windows].find { |record| record[:id] == snapshot[:active_window_id] }
        rectangle = pane_rectangle(snapshot, item[:id])
        return unless rectangle

        cursor_geometry(old_item, item, rectangle)
      end

      def pane_rectangle(snapshot, active_id)
        area_height = [@screen.maxy - 1, 1].max
        rectangles = @frontend.send(:layout_rectangles, snapshot[:tree], 0, 0, @screen.maxx, area_height)
        rectangles.find { |rectangle| rectangle.window_id == active_id }
      end

      def cursor_geometry(old_item, item, rectangle)
        left = rectangle.left
        top = rectangle.top
        width = rectangle.width
        height = rectangle.height
        text_height = [height - 1, 0].max
        old_first, first = cursor_origins(old_item, item, text_height)
        return unless old_first == first && text_height.positive?

        left_column = horizontal_origin(item, width)
        { old_item:, item:, left:, top:, width:, height:, text_height:, first:, left_column: }
      end

      def cursor_origins(old_item, item, text_height)
        [old_item[:point], item[:point]].map do |point|
          visible_origin(point[:row], item[:top_line], text_height)
        end
      end

      def horizontal_origin(item, width)
        point = item[:point]
        line = item[:lines][point[:row]].to_s
        Roded::Frontends::CursesTextGeometry.horizontal_origin(line, point[:col], item[:left_column], width)
      end

      def visible_origin(point, origin, span)
        @frontend.send(:visible_origin, point, origin, span)
      end

      def redraw_cursor_rows(context)
        item = context[:item]
        old_row = context[:old_item][:point][:row]
        new_row = item[:point][:row]
        [old_row, new_row].uniq.each { |row| redraw_row(context, row) }
      end

      def redraw_row(context, row)
        screen_row = context[:top] + row - context[:first]
        return unless screen_row.between?(context[:top], context[:top] + context[:text_height] - 1)

        @frontend.send(:draw_buffer_line, row_arguments(context, row, screen_row))
      end

      def row_arguments(context, row, screen_row)
        item = context[:item]
        CursesRenderContext::BufferLine.new(
          item:, line: item[:lines][row].to_s, buffer_row: row, screen_row:, left: context[:left],
          width: context[:width], left_column: context[:left_column]
        )
      end

      def place_cursor(context)
        @screen.setpos(*screen_position(context))
      end

      def screen_position(context)
        [screen_row(context), screen_column(context)]
      end

      def screen_row(context)
        row = context[:top] + context[:item][:point][:row] - context[:first]
        row.clamp(context[:top], context[:top] + context[:text_height] - 1)
      end

      def screen_column(context)
        item = context[:item]
        point = item[:point]
        line = item[:lines][point[:row]].to_s
        clamp_cursor_column(context, context[:left] + horizontal_offset(line, point, context[:left_column]))
      end

      def horizontal_offset(line, point, left_column)
        cursor_column = Roded::Frontends::CursesTextGeometry.column(line, point[:col])
        origin_column = Roded::Frontends::CursesTextGeometry.column(line, left_column)
        cursor_column - origin_column
      end

      def clamp_cursor_column(context, column)
        column.clamp(context[:left], context[:left] + context[:width] - 1)
      end
    end
  end
end
