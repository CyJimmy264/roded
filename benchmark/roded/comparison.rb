module Roded
  module Benchmarking
    # Rejects incompatible methodology; comparisons may select a subset of a baseline.
    class Comparison
      CONFIG_FIELDS = %w[profile buffers windows samples iterations warmup seed].freeze
      ENVIRONMENT_FIELDS = %w[ruby platform host cpu yjit harness_sha256 qt_platform ruby_options gc_environment
                              gems].freeze

      def initialize(baseline, candidate, threshold:)
        @baseline = baseline
        @candidate = candidate
        @threshold = threshold
        validate_compatibility
      end

      def results
        reference = @baseline.fetch("results").to_h { |row| [key(row), row] }
        @candidate.fetch("results").map do |row|
          previous = reference[key(row)]
          raise ArgumentError, "baseline has no result for #{key(row).join("/")}" unless previous

          compare(previous, row)
        end
      end

      private

      def key(row) = row.values_at("layer", "lines", "scenario")

      def compare(previous, row)
        before = previous.fetch("metrics").fetch("median_ms")
        after = row.fetch("metrics").fetch("median_ms")
        raise ArgumentError, "baseline median must be positive" unless before.positive?

        change = ((after / before) - 1) * 100
        { layer: row.fetch("layer"), lines: row.fetch("lines"), scenario: row.fetch("scenario"),
          baseline_median_ms: before, median_ms: after, change_percent: change,
          p95_change_percent: percent_change(previous, row, "p95_ms"),
          allocations_change_percent: percent_change(previous, row, "allocated_objects_per_operation"),
          regression: change > @threshold }
      end

      def percent_change(previous, row, metric)
        before = previous.fetch("metrics").fetch(metric)
        before.positive? ? ((row.fetch("metrics").fetch(metric) / before) - 1) * 100 : nil
      end

      def validate_compatibility
        unless @baseline.fetch("schema_version") == 1 && @candidate.fetch("schema_version") == 1
          raise ArgumentError, "unsupported benchmark report schema"
        end

        validate_fields("config", CONFIG_FIELDS)
        validate_fields("environment", ENVIRONMENT_FIELDS)
        @candidate.fetch("fixtures").each do |fixture|
          previous = @baseline.fetch("fixtures").find { |item| item.fetch("lines") == fixture.fetch("lines") }
          raise ArgumentError, "incompatible fixture: #{fixture.fetch("lines")} lines" unless previous == fixture
        end
      end

      def validate_fields(section, fields)
        fields.each do |field|
          next if @baseline.fetch(section).fetch(field) == @candidate.fetch(section).fetch(field)

          raise ArgumentError, "incompatible #{section}.#{field}; repeat both runs with the same environment/options"
        end
      end
    end
  end
end
