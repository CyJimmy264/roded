require_relative "../../lib/roded/frontends/qt"

module Roded
  module Benchmarking
    # Drains the real coalescing dispatcher on the GUI thread, then pumps painting.
    class QtFrontend < NullFrontend
      attr_reader :frontend

      def initialize(application)
        super()
        @frontend = Frontends::Qt.new(application)
        @dispatcher = @frontend.instance_variable_get(:@ui_dispatcher)
        @dispatcher.stop
      end

      def handle_command(command) = @frontend.handle_command(command)

      def show
        frontend.view.show
        finish
      end

      def finish
        @dispatcher.send(:drain)
        3.times { QApplication.process_events }
      end

      def close
        @dispatcher.stop
        frontend.view.close
        QApplication.process_events
      end
    end
  end
end
