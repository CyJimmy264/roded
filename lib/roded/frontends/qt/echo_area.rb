require_relative "../../picker_viewport"

module Roded
  module Frontends
    # Displays prompts, feedback, and minibuffer input below editor panes.
    class QtEchoArea
      attr_reader :widget

      def initialize(parent)
        @parent = parent
        @widget = QLabel.new(parent)
        @widget.set_margin(0)
        @widget.set_size_policy(QSizePolicy::Expanding, QSizePolicy::Fixed)
        update_text("")
      end

      def render_minibuffer(payload)
        update_text("#{payload[:prompt]}#{payload[:text]}")
      end

      def render_picker(payload)
        header = "#{payload[:prompt]}#{payload[:query]}"
        rows = PickerViewport.slice(
          payload[:candidates], payload[:selected_index], limit: picker_row_limit
        )
        lines = rows[:candidates].each_with_index.map do |candidate, index|
          "#{index == rows[:selected_index] ? ">" : " "} #{candidate}"
        end
        update_text(([header] + lines).join("\n"))
      end

      def clear
        update_text("")
      end

      def display(message)
        update_text(message.to_s)
      end

      private

      def picker_row_limit
        return 8 unless @widget.is_visible

        height = @parent.height / 2
        return 8 unless height.positive?

        [((height - 8) / 20) - 1, 0].max
      end

      def update_text(text)
        @widget.set_text(text)
        line_count = [text.split("\n", -1).length, 1].max
        @widget.set_fixed_height(@widget.font_metrics.line_spacing * line_count)
      end
    end
  end
end
