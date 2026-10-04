module Roded
  module Frontends
    # Chooses cursor, pane or structural redraws without clearing unchanged frames.
    module CursesLayoutRefreshOperations
      private

      def render_layout(snapshot, force: false)
        geometry = layout_geometry
        return if unchanged_layout?(snapshot, geometry, force)

        horizontal_viewport.retain(snapshot[:windows])
        return if !force && @layout_geometry == geometry && incremental_layout_redraw(snapshot)

        @layout_geometry = geometry
        @layout_snapshot = snapshot
        erase_layout_screen(force)
        draw_layout_windows(snapshot)
        render_overlays
        @screen.refresh
      end

      def incremental_layout_redraw(snapshot)
        CursesCursorRedraw.new(self).call(@layout_snapshot, snapshot) ||
          CursesPaneRedraw.new(self).call(@layout_snapshot, snapshot)
      end

      def layout_geometry
        [@screen.maxx, @screen.maxy, editor_area_height, @minibuffer_state, @picker_state]
      end

      def unchanged_layout?(snapshot, geometry, force)
        !force && @layout_geometry == geometry && @layout_snapshot == snapshot
      end

      def erase_layout_screen(force)
        if !force && @screen.respond_to?(:erase)
          @screen.erase
        else
          @screen.clear
        end
      end

      def draw_layout_windows(snapshot)
        rectangles = layout_rectangles(snapshot[:tree], 0, 0, @screen.maxx, editor_area_height)
        records = snapshot[:windows].to_h { |item| [item[:id], item] }
        rectangles.each { |rectangle| draw_window(records[rectangle.window_id], rectangle) }
        place_active_layout_cursor(snapshot, records, rectangles)
      end

      def place_active_layout_cursor(snapshot, records, rectangles)
        rectangle = rectangles.find { |item| item.window_id == snapshot[:active_window_id] }
        return unless rectangle

        item = records.fetch(rectangle.window_id)
        first, left = window_origin(item, rectangle.width, rectangle.height)
        place_window_cursor(item, first, left, rectangle)
      end
    end
  end
end
