module Roded
  module Benchmarking
    # Consumes updates without retaining snapshots or adding renderer work.
    class NullFrontend
      def page_size(_window_id = nil) = 38

      def handle_command(_command); end

      def finish; end

      def close; end
    end
  end
end
