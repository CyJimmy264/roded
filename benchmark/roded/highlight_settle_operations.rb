module Roded
  module Benchmarking
    # Separately drains deferred color work; foreground latency excludes this phase.
    module HighlightSettleOperations
      def settle_highlighting(timeout: 15)
        return unless application.syntax_highlighting_pending?

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        while application.syntax_highlighting_pending?
          drain_highlight_event
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
          raise "background syntax did not settle" if elapsed > timeout
        end
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
      end

      private

      def drain_highlight_event
        event = application.instance_variable_get(:@event_queue).pop(true)
        raise "unexpected benchmark event: #{event.type}" unless %i[syntax_result resize].include?(event.type)

        application.handle_event(event)
        frontend.finish
      rescue ThreadError
        sleep 0.001
      end
    end
  end
end
