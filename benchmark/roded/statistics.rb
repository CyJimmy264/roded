module Roded
  module Benchmarking
    # Nearest-rank percentiles over individual operations, with GC kept enabled.
    module Statistics
      def self.summarize(samples)
        operations = samples.flatten
        times = operations.map { |operation| operation.fetch(:wall_ns) }.sort
        latency_metrics(times).merge(memory_metrics(operations))
      end

      def self.latency_metrics(times)
        mean = times.sum.fdiv(times.length)
        {
          operations: times.length, median_ms: median(times) / 1_000_000.0,
          p95_ms: times[(times.length * 0.95).ceil - 1] / 1_000_000.0,
          max_ms: times.last / 1_000_000.0, mean_ms: mean / 1_000_000.0,
          operations_per_second: 1_000_000_000.0 / mean
        }
      end

      def self.memory_metrics(operations)
        {
          allocated_objects_per_operation: operations.sum { |item| item.fetch(:allocated_objects) }
                                                     .fdiv(operations.length),
          gc_runs: operations.sum { |item| item.fetch(:gc_runs) },
          gc_ms: operations.sum { |item| item.fetch(:gc_ns) } / 1_000_000.0
        }
      end

      def self.median(sorted)
        middle = sorted.length / 2
        sorted.length.odd? ? sorted[middle].to_f : (sorted[middle - 1] + sorted[middle]) / 2.0
      end
    end
  end
end
