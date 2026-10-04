require "open3"
require_relative "surface"
require_relative "workload"
require_relative "measurement_operations"

module Roded
  module Benchmarking
    # Serializes keystrokes only after detecting each changed caret in the frame.
    class LatencySession
      include LatencyMeasurementOperations

      def initialize(fixture, count:, warmup:, original:)
        @fixture = fixture
        @count = count
        @warmup = warmup
        @original = original
      end

      def run(name, error_path)
        Open3.popen2(*arguments, err: error_path) do |input, output, process|
          connect(input, output, process)
          exercise(name)
        ensure
          stop
        end
      rescue StandardError => e
        raise "#{e.message}\nChild diagnostics: #{File.read(error_path)}"
      end

      private

      def connect(input, output, process)
        @input = input
        @output = output
        @process = process
        @surface = LatencySurface.new
      end

      def arguments
        values = [RbConfig.ruby, File.join(__dir__, "child.rb"), @fixture.line_count.to_s, @fixture.profile]
        values << "--original" if @original
        values
      end

      def stop
        if @process&.alive?
          @input.puts("quit")
          @input.flush
          terminate unless @process.join(5)
          @process.join
        end
        @surface&.close
        @surface = nil
      end

      def terminate
        Process.kill("TERM", @process.pid)
        Process.kill("KILL", @process.pid) unless @process.join(2)
      end
    end
  end
end
