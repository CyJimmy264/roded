module Roded
  module Benchmarking
    # CLI controls for deterministic fixtures and actual-file reproductions.
    module LatencyConfiguration
      private

      def validate(arguments)
        valid = arguments.empty? && valid_counts? && valid_workloads? && valid_interval?
        raise OptionParser::InvalidArgument, "invalid fixture, counts or workload" unless valid
      end

      def valid_interval? = @config[:dispatcher_ms].nil? || @config[:dispatcher_ms].between?(1, 1000)

      def valid_counts?
        @config[:lines] >= 1500 && @config[:iterations].positive? && @config[:warmup] >= 0 &&
          @config[:buffers].positive? && valid_position? && valid_geometry? && valid_line_length?
      end

      def valid_line_length? = @config[:line_length].nil? || @config[:line_length].positive?

      def valid_position?
        @config[:start_col] >= 0 && (@config[:start_row].nil? || @config[:start_row] >= 0)
      end

      def valid_geometry? = @config[:width].between?(200, 1920) && @config[:height].between?(200, 1080)

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
          options.on("--dispatcher-ms N", Integer) { |value| @config[:dispatcher_ms] = value }
          reproduction_options(options)
        end
      end

      def reproduction_options(options)
        %i[buffers start_col line_length start_row width height].each do |key|
          options.on("--#{key.to_s.tr("_", "-")} N", Integer) { |value| @config[key] = value }
        end
        options.on("--file PATH") { |value| @config[:file] = File.expand_path(value) }
        options.on("--extra-file PATH") { |value| @config[:extra_files] << File.expand_path(value) }
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
