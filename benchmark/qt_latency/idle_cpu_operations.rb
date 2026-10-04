module Roded
  module Benchmarking
    # Samples the editor process CPU clock before any measured keystrokes.
    module LatencyIdleCpuOperations
      def measure_idle_cpu(interval, single_shot)
        before = cpu_sample
        sleep 1
        after = cpu_sample
        elapsed = after.fetch("monotonic_ns") - before.fetch("monotonic_ns")
        cpu = after.fetch("cpu_ns") - before.fetch("cpu_ns")
        @idle_cpu = { dispatcher_interval_ms: interval, dispatcher_single_shot: single_shot,
                      wall_ms: elapsed / 1_000_000.0,
                      cpu_ms: cpu / 1_000_000.0, one_core_percent: cpu.fdiv(elapsed) * 100 }
      end

      def cpu_sample
        @input.puts("cpu")
        @input.flush
        read_record("cpu")
      end
    end
  end
end
