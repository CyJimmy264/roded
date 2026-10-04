require "optparse"

module Roded
  module Benchmarking
    # Parses and validates the reproducible workload separately from report controls.
    class Options
      LAYERS = %w[core application curses qt].freeze
      DEFAULTS = { lines: [1500, 5000, 10_000], layers: %w[core application], profile: "plain",
                   buffers: 4, windows: 1, samples: 5, iterations: 10, warmup: 2, seed: 264 }.freeze

      attr_reader :config, :controls

      def initialize
        @config = DEFAULTS.dup
        @controls = { threshold: 20.0 }
      end

      def parse(arguments)
        parser.parse!(arguments)
        raise ArgumentError, "unexpected arguments: #{arguments.join(" ")}" unless arguments.empty?
        return if controls[:list]

        validate_workload
        validate_measurement
        validate_controls
      end

      private

      def parser
        OptionParser.new do |options|
          options.banner = "Usage: bundle exec ruby benchmark/run.rb [options]"
          workload_options(options)
          measurement_options(options)
          report_options(options)
          options.on("--list", "List scenarios without running") { controls[:list] = true }
          options.on("-h", "--help") { print_help(options) }
        end
      end

      def print_help(options)
        puts options
        exit 0
      end

      # Declarative command-line option tables.
      # rubocop:disable Metrics/AbcSize
      def workload_options(options)
        options.on("--lines LIST", "Line counts >= 1500 (default 1500,5000,10000)") do |value|
          config[:lines] = value.split(",").map { |item| Integer(item, 10) }.uniq
        end
        options.on("--layers LIST", "core,application,curses,qt (default core,application)") do |value|
          config[:layers] = value.split(",").uniq
        end
        options.on("--profile NAME", "plain, ruby, unicode") { |value| config[:profile] = value }
        options.on("--scenarios REGEX", "Select scenario names") { |value| controls[:pattern] = Regexp.new(value) }
      end

      def measurement_options(options)
        %i[buffers windows samples iterations warmup seed].each do |name|
          options.on("--#{name} N", Integer) { |value| config[name] = value }
        end
        options.on("--qt-xvfb", "Use xcb in a private xvfb-run session") { controls[:xvfb] = true }
      end

      def report_options(options)
        options.on("--output PATH", "Write JSON, including raw samples") { |value| controls[:output] = value }
        options.on("--baseline PATH", "Compare with compatible JSON report") { |value| controls[:baseline] = value }
        options.on("--max-regression PERCENT", Float, "Median threshold (default 20%)") do |value|
          controls[:threshold] = value
        end
        options.on("--fail-on-regression", "Exit 1 when the median exceeds the threshold") { controls[:fail] = true }
      end
      # rubocop:enable Metrics/AbcSize

      def validate_workload
        unless config[:lines].any? && config[:lines].all? { |n| n >= 1500 }
          raise ArgumentError, "line counts must be >= 1500"
        end
        raise ArgumentError, "unknown/empty layers" if config[:layers].empty? || (config[:layers] - LAYERS).any?
      end

      def validate_measurement
        raise ArgumentError, "unknown profile" unless Fixture::PROFILES.include?(config[:profile])
        raise ArgumentError, "buffers must be >= 2" if config[:buffers] < 2

        validate_positive
        raise ArgumentError, "warmup must be nonnegative" if config[:warmup].negative?
      end

      def validate_positive
        %i[windows samples iterations].each do |name|
          raise ArgumentError, "#{name} must be positive" unless config[name].positive?
        end
      end

      def validate_controls
        validate_threshold
        raise ArgumentError, "--fail-on-regression requires --baseline" if controls[:fail] && !controls[:baseline]
        return unless controls[:xvfb] && !config[:layers].include?("qt")

        raise ArgumentError, "--qt-xvfb requires the qt layer"
      end

      def validate_threshold
        return if controls[:threshold].finite? && controls[:threshold] >= 0

        raise ArgumentError, "regression threshold must be finite and nonnegative"
      end
    end
  end
end
