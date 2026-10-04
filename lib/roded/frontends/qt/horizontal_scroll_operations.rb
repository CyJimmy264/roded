module Roded
  module Frontends
    # Synchronizes Qt's pixel scrollbar with the core's character-based origin.
    module QtHorizontalScrollOperations
      private

      def subscribe_horizontal_scroll
        return if @horizontal_scroll_subscribed || !@horizontal_scroll_callback

        @editor.horizontal_scroll_bar.connect("valueChanged(int)") { |_value| report_horizontal_scroll }
        @horizontal_scroll_subscribed = true
      end

      def report_horizontal_scroll
        return if @horizontal_scroll_feedback_suspended
        return unless @snapshot && @horizontal_scroll_callback

        left_column = QtCursorMapper.left_column_at_viewport(@editor, @rendered_text, @snapshot)
        signature = [@window_id, @snapshot.object_id, left_column]
        return if signature == @last_horizontal_scroll_report

        @last_horizontal_scroll_report = signature
        @horizontal_scroll_callback.call(left_column:, window_id: @window_id)
      end

      def reveal_horizontal_cursor
        with_horizontal_scroll_feedback_suspended do
          @editor.ensure_cursor_visible
          reveal_caret_cell
        end
        report_horizontal_scroll
      end

      def reveal_caret_cell
        width = QtCursorMapper.caret_width(@editor, @rendered_text, @snapshot)
        right = @editor.cursor_rect.x + width + QtCursorMapper.document_margin(@editor)
        overflow = (right - @editor.viewport.width).ceil
        return unless overflow.positive?

        scroll_bar = @editor.horizontal_scroll_bar
        scroll_bar.set_value(scroll_bar.value + overflow)
      end

      def with_horizontal_scroll_feedback_suspended
        # Qt needs valueChanged to scroll every painted row, including unchanged ones.
        previous_state = @horizontal_scroll_feedback_suspended
        @horizontal_scroll_feedback_suspended = true
        yield
      ensure
        @horizontal_scroll_feedback_suspended = previous_state
      end

      def restore_horizontal_scroll(snapshot, text)
        origin = snapshot.fetch(:left_column, 0).to_i
        return unless QtCursorMapper.horizontal_origin_visible?(@editor, text, snapshot, origin)

        offset = QtCursorMapper.horizontal_offset(@editor, text, snapshot.fetch(:point).fetch(:row), origin, snapshot)
        @editor.horizontal_scroll_bar.set_value(offset)
      end
    end
  end
end
