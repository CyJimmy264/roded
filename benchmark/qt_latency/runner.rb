require_relative "../roded/fixture"
require_relative "../roded/statistics"
require_relative "../roded/environment"
require_relative "../roded/report"
require_relative "session"
require_relative "file_fixture"
require_relative "configuration"
require "optparse"

module Roded
  module Benchmarking
    # A separate report schema: server-side frame latency, not manually drained work.
    class LatencyRunner
      include LatencyConfiguration

      PHASE_EDGES = {
        native_delivery: %w[sent_ns input_received], core_queue: %w[input_received core_started],
        core_and_snapshot: %w[core_started snapshot_posted], dispatcher_wait: %w[snapshot_posted widget_started],
        widget_apply: %w[widget_started widget_finished], frame_detection: %w[widget_finished frame_detected_ns]
      }.freeze

      def initialize(arguments)
        @config = { lines: 1500, profile: "plain", iterations: 40, warmup: 4,
                    workloads: LatencyWorkload::NAMES, original: false, dispatcher_ms: nil, buffers: 1, start_col: 4,
                    start_row: nil, width: 960, height: 640, extra_files: [] }
        @idle_samples = []
        @output = "tmp/benchmarks/qt-key-latency.json"
        parser.parse!(arguments)
        validate(arguments)
      end

      def run
        fixture = LatencyFileFixture.build(@config)
        results = Dir.mktmpdir("roded-key-latency-") { |directory| measure(fixture, directory) }
        report = { schema_version: 1, workload: "qt_x11_key_to_caret_frame", config: @config,
                   fixture: fixture.metadata, extra_fixtures: extra_metadata,
                   environment: environment,
                   latency_harness_sha256: harness_digest, idle_process_cpu: @idle_samples, results: }
        Report.write(@output, report)
        results.each { |row| puts "#{row[:scenario]}: #{row[:metrics].slice(:median_ms, :p95_ms, :max_ms)}" }
        puts "Report: #{File.expand_path(@output)}"
      end

      private

      def measure(fixture, directory)
        @config[:workloads].flat_map do |name|
          warn "Measuring real Qt keys: #{name} (#{fixture.line_count} #{fixture.profile} rows)"
          samples = measure_workload(fixture, name, File.join(directory, "#{name}.log"))
          samples.group_by { |sample| sample[:scenario] }
                 .map { |scenario, samples| summarize(scenario, samples) }
        end
      end

      def measure_workload(fixture, name, error_path)
        session = LatencySession.new(fixture, config: @config)
        session.run(name, error_path).tap { @idle_samples << session.idle_cpu.merge(workload: name) }
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

      def extra_metadata = @config[:extra_files].map { |path| LatencyFileFixture.new(path).metadata }

      def environment
        Environment.capture.merge(qt_gem: Gem::Specification.find_by_name("qt").version.to_s)
      end

      def harness_digest
        files = Dir[File.join(__dir__, "*.rb")] + [File.expand_path("../qt_key_latency.rb", __dir__)]
        Digest::SHA256.hexdigest(files.sort.map { |path| "#{File.basename(path)}\0#{File.read(path)}" }.join("\0"))
      end
    end
  end
end
