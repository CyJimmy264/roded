module Roded
  module Frontends
    # Plain-text layout scrolls in logical lines, matching the core viewport.
    module QtVerticalScrollOperations
      private

      def subscribe_layout
        return if @layout_subscribed

        @editor.on(:resize) { restore_scroll(@snapshot) if @snapshot }
        @layout_subscribed = true
      end

      def restore_scroll(snapshot)
        scroll_bar = @editor.vertical_scroll_bar
        scroll_bar.set_single_step(1)
        scroll_bar.set_value(visible_origin(snapshot))
        @editor.viewport.update
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
