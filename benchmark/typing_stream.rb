#!/usr/bin/env ruby

require_relative "../lib/roded"
require_relative "roded/cli"

module Roded
  module Benchmarking
    # Measures consecutive edits without resetting the document or priming an edited-text cache.
    class TypingStreamRunner < Runner
      private

      def exercise(work, scenario, timed:)
        unless @prepared_work.equal?(work)
          scenario.prepare.call(work)
          work.render
          @prepared_work = work
        end
        measurement = timed ? measure_operation(work, scenario) : perform_operation(work, scenario)
        raise "typing stream verification failed" unless scenario.verify.call(work)

        measurement
      end
    end

    # Uses the same fixtures, isolation, operation counters and reports as the main suite.
    class TypingStream
      def initialize(arguments)
        @mode = "plain"
        @config = { lines: [1500], layers: ["curses"], samples: 3, iterations: 20,
                    warmup: 0, buffers: 4, windows: 1, seed: 1 }
        @output = "tmp/benchmarks/typing-stream.json"
        parse(arguments)
        @config[:profile] = @mode == "ruby" ? "ruby" : "plain"
      end

      def run
        Isolation.run(xvfb: false) do
          report = TypingStreamRunner.new(@config).run([scenario])
          report[:config] = @config.merge(mode: @mode, workload: "consecutive_typing")
          report[:environment] = Environment.capture.merge(stream_sha256: Digest::SHA256.file(__FILE__).hexdigest)
          Report.write(@output, report)
          Report.print(report)
          puts "Report: #{File.expand_path(@output)}"
        end
      end

      private

      def parse(arguments)
        option_parser.parse!(arguments)
        raise OptionParser::InvalidArgument, "unexpected arguments" unless arguments.empty?
        raise OptionParser::InvalidArgument, "counts must be positive" unless
          @config.values_at(:samples, :iterations).all?(&:positive?) && @config[:lines].first >= 1500
      end

      def option_parser
        OptionParser.new do |options|
          options.banner = "Usage: bundle exec ruby benchmark/typing_stream.rb [options]"
          add_count_options(options)
          add_workload_options(options)
          options.on("--help") do
            puts options
            exit
          end
        end
      end

      def add_count_options(options)
        options.on("--lines N", Integer) { |value| @config[:lines] = [value] }
        options.on("--samples N", Integer) { |value| @config[:samples] = value }
        options.on("--iterations N", Integer) { |value| @config[:iterations] = value }
      end

      def add_workload_options(options)
        options.on("--layer NAME", %w[core application curses qt]) { |value| @config[:layers] = [value] }
        options.on("--mode NAME", SyntaxHighlighter::MODES.map(&:to_s)) { |value| @mode = value }
        options.on("--output PATH") { |value| @output = value }
      end

      def scenario
        Scenario.new(
          "edit.typing_stream", ->(work) { work.documents.each { |buffer| buffer.major_mode = @mode.to_sym } },
          ->(work) { work.dispatch(:insert_char, char: (97 + (work.window.point[:col] % 26)).chr) },
          ->(work) { valid_point?(work) }
        )
      end

      def valid_point?(work)
        inserted = inserted_characters(work)
        work.window.point == { row: work.middle, col: 12 + inserted } && inserted.positive?
      end

      def inserted_characters(work)
        work.buffer.lines[work.middle].length - work.fixture.text.split("\n")[work.middle].length
      end
    end
  end
end

Roded::Benchmarking::TypingStream.new(ARGV).run if $PROGRAM_NAME == __FILE__
