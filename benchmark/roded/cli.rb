require_relative "fixture"
require_relative "scenarios"
require_relative "runner"
require_relative "environment"
require_relative "comparison"
require_relative "report"
require_relative "options"
require_relative "isolation"

module Roded
  module Benchmarking
    # Standalone entry point; benchmark work is excluded from rake's default.
    class CLI
      def initialize
        @options = Options.new
        @config = @options.config
        @controls = @options.controls
      end

      def run(arguments)
        @options.parse(arguments)
        return list if @controls[:list]

        execute
      rescue OptionParser::ParseError, ArgumentError, KeyError, RegexpError => e
        warn "Benchmark error: #{e.message}"
        2
      end

      private

      def execute
        report = isolated_run(selected_scenarios)
        compare(report) if @controls[:baseline]
        save(report)
        @controls[:fail] && report.fetch(:comparison).any? { |row| row[:regression] } ? 1 : 0
      end

      def save(report)
        default_path = "tmp/benchmarks/#{Time.now.utc.strftime("%Y%m%dT%H%M%S")}-#{Process.pid}.json"
        path = @controls[:output] || default_path
        Report.write(path, report)
        Report.print(report)
        puts "\nReport: #{File.expand_path(path)}"
      end

      def selected_scenarios
        pattern = @controls[:pattern]
        scenarios = Scenarios.all.select { |scenario| !pattern || pattern.match?(scenario.name) }
        raise ArgumentError, "no scenarios matched" if scenarios.empty?

        scenarios
      end

      def list
        selected_scenarios.each { |scenario| puts scenario.name }
        0
      end

      def isolated_run(scenarios)
        Isolation.run(xvfb: @controls[:xvfb]) do
          result = Runner.new(@config).run(scenarios)
          { schema_version: 1, config: @config, environment: Environment.capture, **result }
        end
      end

      def compare(report)
        baseline = JSON.parse(File.read(@controls[:baseline]))
        candidate = JSON.parse(JSON.generate(report))
        report[:comparison] = Comparison.new(baseline, candidate, threshold: @controls[:threshold]).results
      rescue Errno::ENOENT, JSON::ParserError => e
        raise ArgumentError, "cannot read baseline: #{e.message}"
      end
    end
  end
end
