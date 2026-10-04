module Roded
  module Frontends
    # Keeps the Qt pixel scrollbar aligned with the core's line-based viewport.
    module QtVerticalScrollOperations
      private

      def subscribe_layout
        return if @layout_subscribed

        @editor.on(:resize) { restore_scroll(@snapshot) if @snapshot }
        @layout_subscribed = true
      end

      def restore_scroll(snapshot)
        scroll_bar = @editor.vertical_scroll_bar
        rectangle = @editor.cursor_rect
        scroll_bar.set_single_step([rectangle.height, 1].max)
        scroll_bar.set_value(vertical_scroll_offset(snapshot, rectangle, scroll_bar))
        @editor.viewport.update
      end

      def vertical_scroll_offset(snapshot, rectangle, scroll_bar)
        caret_y = scroll_bar.value + rectangle.y - @editor.document.property("documentMargin").round
        row_delta = snapshot.fetch(:point).fetch(:row) - visible_origin(snapshot)
        caret_y - (row_delta * scroll_bar.single_step)
      end

      def visible_origin(snapshot)
        origin = snapshot.fetch(:top_line, 0).to_i
        point_row = snapshot.fetch(:point).fetch(:row).to_i
        scroll_bar = @editor.vertical_scroll_bar
        page_size = scroll_bar.page_step / [scroll_bar.single_step, 1].max
        return point_row if point_row < origin
        return point_row - page_size + 1 if page_size.positive? && point_row >= origin + page_size

        origin
      end

      def schedule_scroll_restore
        return if @scroll_timer&.is_active

        @scroll_timer ||= QTimer.new(@editor)
        @scroll_timer.set_single_shot(true)
        @scroll_timer.connect("timeout") do |_payload|
          restore_pending_viewport
        end
        @scroll_timer.set_interval(0)
        @scroll_timer.start
      end

      def restore_pending_viewport
        return unless @snapshot

        restore_scroll(@snapshot)
        return unless @rendered_text
        return if QtCursorMapper.horizontal_origin_visible?(
          @editor, @rendered_text, @snapshot, @snapshot.fetch(:left_column, 0)
        )

        reveal_horizontal_cursor
      end
    end
  end
end
