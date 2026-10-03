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
        lines = payload[:candidates].each_with_index.map do |candidate, index|
          "#{index == payload[:selected_index] ? ">" : " "} #{candidate}"
        end
        @widget.set_text(([header] + lines).join("\n"))
      end

      def clear
        @widget.clear
      end

      def display(message)
        @widget.set_text(message.to_s)
      end
    end
  end
end
