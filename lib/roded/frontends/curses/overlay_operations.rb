module Roded
  module Frontends
    # Draws the echo/minibuffer and picker over editor content.
    module CursesOverlayOperations
      private

      def render_minibuffer_overlay
        return unless @minibuffer_state

        @minibuffer_view.render(
          prompt: @minibuffer_state[:prompt],
          text: @minibuffer_state[:text],
          cursor: @minibuffer_state[:cursor]
        )
      end

      def render_picker_overlay
        return unless @picker_state

        render_picker_rows(picker_viewport_rows)
      end

      def render_picker_rows(rows)
        start_row = editor_area_height
        rows[:candidates].each_with_index do |candidate, index|
          row = start_row + index
          marker = index == rows[:selected_index] ? "> " : "  "
          @screen.setpos(row, 0)
          @screen.clrtoeol
          write_at(row, 0, "#{marker}#{candidate}", @screen.maxx)
        end
      end

      def picker_viewport_rows
        PickerViewport.slice(
          @picker_state[:candidates], @picker_state[:selected_index], limit: [@screen.maxy - 3, 0].max
        )
      end

      def editor_area_height
        [@screen.maxy - 1 - picker_row_count, 1].max
      end

      def picker_row_count
        @picker_state ? picker_viewport_rows[:candidates].length : 0
      end
    end
  end
end
