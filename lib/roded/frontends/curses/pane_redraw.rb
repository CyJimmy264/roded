module Roded
  module Frontends
    # Redraws changed panes while leaving other panes and the echo area untouched.
    class CursesPaneRedraw
      def initialize(frontend)
        @frontend = frontend
        @screen = frontend.instance_variable_get(:@screen)
      end

      def call(previous, snapshot)
        return false unless previous && previous[:tree] == snapshot[:tree]

        records = snapshot[:windows].to_h { |item| [item[:id], item] }
        old_records = previous[:windows].to_h { |item| [item[:id], item] }
        return false unless same_window_ids?(old_records, records)

        rectangles = pane_rectangles(snapshot)
        redraw_changed_panes(records, old_records, rectangles)
        finish_frame(snapshot, records, rectangles)
        true
      end

      private

      def same_window_ids?(old_records, records)
        old_records.keys.sort == records.keys.sort
      end

      def finish_frame(snapshot, records, rectangles)
        @frontend.send(:place_active_layout_cursor, snapshot, records, rectangles)
        @frontend.instance_variable_set(:@layout_snapshot, snapshot)
        @screen.refresh
      end

      def pane_rectangles(snapshot)
        @frontend.send(:layout_rectangles, snapshot[:tree], 0, 0, @screen.maxx,
                       @frontend.send(:editor_area_height))
      end

      def redraw_changed_panes(records, old_records, rectangles)
        rectangles.each do |rectangle|
          item = records.fetch(rectangle.window_id)
          next if item == old_records.fetch(rectangle.window_id)

          erase_pane_text(rectangle)
          @frontend.send(:draw_window, item, rectangle)
        end
      end

      def erase_pane_text(rectangle)
        padding = " " * rectangle.width
        [rectangle.height - 1, 0].max.times do |offset|
          @frontend.send(:write_at, rectangle.top + offset, rectangle.left, padding, rectangle.width)
        end
      end
    end
  end
end
