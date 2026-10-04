module Roded
  module Benchmarking
    # Separately drains deferred color work; foreground latency excludes this phase.
    module HighlightSettleOperations
      FEEDBACK_EVENTS = %i[syntax_result resize horizontal_scroll].freeze

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

      def drain_pending_feedback
        return unless frontend

        loop { apply_benchmark_feedback(application.instance_variable_get(:@event_queue).pop(true)) }
      rescue ThreadError
        nil
      end

      def drain_highlight_event
        event = application.instance_variable_get(:@event_queue).pop(true)
        apply_benchmark_feedback(event)
      rescue ThreadError
        sleep 0.001
      end

      def apply_benchmark_feedback(event)
        raise "unexpected benchmark event: #{event.type}" unless FEEDBACK_EVENTS.include?(event.type)

        application.handle_event(event)
        frontend.finish
      end
    end
  end
end
