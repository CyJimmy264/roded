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

        rows = PickerViewport.slice(
          @picker_state[:candidates], @picker_state[:selected_index], limit: [@screen.maxy - 2, 0].max
        )
        render_picker_rows(rows)
      end

      def render_picker_rows(rows)
        start_row = [@screen.maxy - rows[:candidates].length - 2, 0].max
        rows[:candidates].each_with_index do |candidate, index|
          marker = index == rows[:selected_index] ? "> " : "  "
          write_at(start_row + index, 0, "#{marker}#{candidate}", @screen.maxx)
        end
      end
    end
  end
end
