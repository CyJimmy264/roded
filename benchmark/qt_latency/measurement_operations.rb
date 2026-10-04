require "io/wait"

module Roded
  module Benchmarking
    # Frame detection includes a 1 ms poll and IPC overhead; reports an upper bound.
    module LatencyMeasurementOperations
      def exercise(name)
        @previous = read_record("ready")
        focus
        wait_frame(@previous.fetch("caret"))
        oracle = LatencyWorkload.new(name, @fixture)
        Array.new(@warmup + @count) do |index|
          scenario, key = oracle.action(index)
          sample = measure_key(scenario, key, index, oracle)
          sample unless index < @warmup
        end.compact
      end

      def measure_key(scenario, key, index, oracle)
        started = now
        @surface.key(key)
        record = read_record("rendered")
        validate_record(record, index)
        wait_frame(record.fetch("caret"), @previous.fetch("caret"))
        sample = measurement(scenario, key, started, record)
        oracle.verify(record, scenario)
        @previous = record
        sample
      end

      def validate_record(record, index)
        raise "unexpected key sequence" unless record.fetch("sequence") == index + 1
        return if record.fetch("horizontal_scroll") == @previous.fetch("horizontal_scroll")

        raise "caret-only frame detection cannot measure horizontal scrolling; reduce typing iterations"
      end

      def measurement(scenario, key, started, record)
        detected = now
        { scenario:, key:, sent_ns: started, frame_detected_ns: detected,
          phases_ns: record.fetch("phases_ns"), wall_ns: detected - started }
      end

      def focus
        ids, _stderr, status = Open3.capture3("xdotool", "search", "--onlyvisible", "--name", "^Roded$")
        raise "could not find isolated editor" unless status.success? && ids.lines.length == 1
        return if system("xdotool", "windowfocus", "--sync", ids.strip)

        raise "could not focus isolated editor"
      end

      def read_record(type)
        raise "timed out waiting for #{type}" unless @output.wait_readable(15)

        line = @output.gets
        raise "editor exited before #{type}" unless line

        record = JSON.parse(line)
        raise "unexpected child record: #{record}" unless record.fetch("type") == type

        record
      end

      def wait_frame(current, previous = nil)
        raise "unchanged caret geometry cannot prove a new frame" if current == previous

        deadline = now + 5_000_000_000
        until @surface.visible?(current, previous)
          raise "timed out waiting for painted caret" if now >= deadline

          sleep 0.001
        end
      end

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
    end
  end
end
