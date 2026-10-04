require_relative "../roded/fixture"
require_relative "../roded/statistics"
require_relative "../roded/environment"
require_relative "../roded/report"
require_relative "session"
require "optparse"

module Roded
  module Benchmarking
    # A separate report schema: server-side frame latency, not manually drained work.
    class LatencyRunner
      PHASE_EDGES = {
        native_delivery: %w[sent_ns input_received], core_queue: %w[input_received core_started],
        core_and_snapshot: %w[core_started snapshot_posted], dispatcher_wait: %w[snapshot_posted widget_started],
        widget_apply: %w[widget_started widget_finished], frame_detection: %w[widget_finished frame_detected_ns]
      }.freeze

      def initialize(arguments)
        @config = { lines: 1500, profile: "plain", iterations: 40, warmup: 4,
                    workloads: LatencyWorkload::NAMES, original: false }
        @output = "tmp/benchmarks/qt-key-latency.json"
        parser.parse!(arguments)
        validate(arguments)
      end

      def run
        fixture = Fixture.new(line_count: @config[:lines], profile: @config[:profile])
        results = Dir.mktmpdir("roded-key-latency-") { |directory| measure(fixture, directory) }
        report = { schema_version: 1, workload: "qt_x11_key_to_caret_frame", config: @config,
                   fixture: fixture.metadata, environment: environment,
                   latency_harness_sha256: harness_digest, results: }
        Report.write(@output, report)
        results.each { |row| puts "#{row[:scenario]}: #{row[:metrics].slice(:median_ms, :p95_ms, :max_ms)}" }
        puts "Report: #{File.expand_path(@output)}"
      end

      private

      def measure(fixture, directory)
        @config[:workloads].flat_map do |name|
          warn "Measuring real Qt keys: #{name} (#{fixture.line_count} #{fixture.profile} rows)"
          session = LatencySession.new(fixture, count: @config[:iterations],
                                                warmup: @config[:warmup], original: @config[:original])
          session.run(name, File.join(directory, "#{name}.log")).group_by { |sample| sample[:scenario] }
                 .map { |scenario, samples| summarize(scenario, samples) }
        end
      end

      def summarize(scenario, samples)
        { scenario:, raw_samples: samples,
          metrics: Statistics.latency_metrics(samples.map { |sample| sample[:wall_ns] }.sort),
          phase_metrics: PHASE_EDGES.transform_values { |edges| phase_metrics(samples, edges) } }
      end

      def phase_metrics(samples, edges)
        times = samples.map do |sample|
          timestamps = sample[:phases_ns].merge("sent_ns" => sample[:sent_ns],
                                                "frame_detected_ns" => sample[:frame_detected_ns])
          elapsed = timestamps.fetch(edges.last) - timestamps.fetch(edges.first)
          raise "out-of-order phase timestamps: #{timestamps}" if elapsed.negative?

          elapsed
        end
        Statistics.latency_metrics(times.sort)
      end

      def environment
        Environment.capture.merge(qt_gem: Gem::Specification.find_by_name("qt").version.to_s)
      end

      def harness_digest
        files = Dir[File.join(__dir__, "*.rb")] + [File.expand_path("../qt_key_latency.rb", __dir__)]
        Digest::SHA256.hexdigest(files.sort.map { |path| "#{File.basename(path)}\0#{File.read(path)}" }.join("\0"))
      end

      def validate(arguments)
        valid = arguments.empty? && @config[:lines] >= 1500 && @config[:iterations].positive? &&
                @config[:warmup] >= 0 && valid_workloads?
        raise OptionParser::InvalidArgument, "invalid fixture, counts or workload" unless valid
      end

      def valid_workloads?
        Fixture::PROFILES.include?(@config[:profile]) && !@config[:workloads].empty? &&
          (@config[:workloads] - LatencyWorkload::NAMES).empty?
      end

      def parser
        OptionParser.new do |options|
          fixture_options(options)
          count_options(options)
          options.on("--original") { @config[:original] = true }
          options.on("--output PATH") { |value| @output = value }
        end
      end

      def fixture_options(options)
        options.on("--lines N", Integer) { |value| @config[:lines] = value }
        options.on("--profile NAME") { |value| @config[:profile] = value }
        options.on("--workloads NAMES", Array) { |value| @config[:workloads] = value }
      end

      def count_options(options)
        options.on("--iterations N", Integer) { |value| @config[:iterations] = value }
        options.on("--warmup N", Integer) { |value| @config[:warmup] = value }
      end
    end
  end
end
