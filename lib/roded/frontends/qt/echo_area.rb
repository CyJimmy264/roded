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

      def clear
        @widget.clear
      end

      def display(message)
        @widget.set_text(message.to_s)
      end
    end
  end
end
