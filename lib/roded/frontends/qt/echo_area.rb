require_relative "../../picker_viewport"

module Roded
  module Frontends
    # Displays prompts, feedback, and minibuffer input below editor panes.
    class QtEchoArea
      attr_reader :widget

      def initialize(parent)
        @widget = QLabel.new(parent)
      end

      def render_minibuffer(payload)
        @widget.set_text("#{payload[:prompt]}#{payload[:text]}")
      end

      def render_picker(payload)
        header = "#{payload[:prompt]}#{payload[:query]}"
        rows = PickerViewport.slice(
          payload[:candidates], payload[:selected_index], limit: picker_row_limit
        )
        lines = rows[:candidates].each_with_index.map do |candidate, index|
          "#{index == rows[:selected_index] ? ">" : " "} #{candidate}"
        end
        @widget.set_text(([header] + lines).join("\n"))
      end

      def clear
        @widget.clear
      end

      def display(message)
        @widget.set_text(message.to_s)
      end

      private

      def picker_row_limit
        return 8 unless @widget.is_visible

        height = @widget.height
        return 8 unless height.positive?

        [((height - 8) / 20) - 1, 0].max
      end
    end
  end
end
