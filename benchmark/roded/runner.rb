require_relative "workspace"
require_relative "statistics"

module Roded
  module Benchmarking
    # Measures only the operation and renderer flush; setup/assertions stay outside.
    class Runner
      def initialize(config, output: $stderr)
        @config = config
        @output = output
      end

      def run(scenarios)
        fixtures = @config.fetch(:lines).to_h do |lines|
          [lines, Fixture.new(line_count: lines, profile: @config.fetch(:profile))]
        end
        rows = tasks(fixtures, scenarios).map.with_index do |(layer, fixture, scenario), index|
          @output.puts "[#{index + 1}] #{layer} #{fixture.line_count} #{scenario.name}"
          measure_scenario(layer, fixture, scenario)
        end
        { fixtures: fixtures.values.map(&:metadata), results: rows }
      end

      private

      def tasks(fixtures, scenarios)
        @config.fetch(:layers).product(fixtures.values, scenarios).shuffle(random: Random.new(@config.fetch(:seed)))
      end

      def measure_scenario(layer, fixture, scenario)
        samples = Array.new(@config.fetch(:samples)) { measure_sample(layer, fixture, scenario) }
        { layer:, lines: fixture.line_count, scenario: scenario.name,
          metrics: Statistics.summarize(samples), samples: }
      end

      def measure_sample(layer, fixture, scenario)
        work = Workspace.new(layer:, fixture:, buffer_count: @config.fetch(:buffers),
                             window_count: @config.fetch(:windows))
        @config.fetch(:warmup).times { exercise(work, scenario, timed: false) }
        GC.start
        Array.new(@config.fetch(:iterations)) { exercise(work, scenario, timed: true) }
      ensure
        work&.close
      end

      def exercise(work, scenario, timed:)
        work.reset
        scenario.prepare.call(work)
        work.render
        measurement = timed ? measure_operation(work, scenario) : perform_operation(work, scenario)
        raise "benchmark verification failed: #{scenario.name}" unless scenario.verify.call(work)

        measurement
      end

      def perform_operation(work, scenario)
        scenario.action.call(work)
        work.frontend.finish
      end

      def measure_operation(work, scenario)
        allocated = GC.stat(:total_allocated_objects)
        gc_count = GC.stat(:count)
        gc_time = GC.total_time
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
        perform_operation(work, scenario)
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) - started
        { wall_ns: elapsed, allocated_objects: GC.stat(:total_allocated_objects) - allocated,
          gc_runs: GC.stat(:count) - gc_count, gc_ns: GC.total_time - gc_time }
      end
    end
  end
end
