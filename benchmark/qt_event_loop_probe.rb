#!/usr/bin/env ruby

require "rbconfig"

# Start a private X server before loading Qt, just like the main benchmark CLI.
if ARGV.include?("--qt-xvfb") && ENV["RODED_EVENT_LOOP_PROBE_XVFB"] != "1"
  exec({ "RODED_EVENT_LOOP_PROBE_XVFB" => "1" }, "xvfb-run", "-a", "-s", "-screen 0 1280x800x24",
       RbConfig.ruby, __FILE__, *ARGV)
end

require_relative "../lib/roded"
require_relative "../lib/roded/frontends/qt"
require_relative "roded/isolation"
require_relative "roded/environment"
require "json"
require "optparse"

module Roded
  module Benchmarking
    # Tests real QApplication.exec, with no Ruby callback until the finish timer.
    class QtEventLoopProbe
      def initialize(original: false)
        @original = original
        @gaps = []
        @stopped = false
      end

      def run
        @application = QApplication.new(0, ["roded-qt-event-loop-probe"])
        prepare_timer
        start_ticker
        started = now
        @original ? @application.exec : Frontends::QtEventLoop.run(@application)
        @stopped = true
        @ticker.join
        result((now - started) * 1000)
      ensure
        stop_probe
      end

      private

      def stop_probe
        @stopped = true
        @ticker&.join
        @timer&.stop
        @application&.dispose
      end

      def prepare_timer
        @timer = QTimer.new
        @timer.set_interval(400)
        @timer.connect("timeout") do
          @timer.stop
          QApplication.quit
        end
        @timer.start
      end

      def start_ticker
        ready = Queue.new
        @ticker = Thread.new { tick(ready) }
        ready.pop
      end

      def tick(ready)
        previous = now
        ready << true
        until @stopped
          sleep 0.001
          current = now
          @gaps << ((current - previous) * 1000)
          previous = current
        end
      end

      def result(elapsed)
        maximum = @gaps.max.to_f
        responsive = @gaps.length >= 50 && maximum < 150
        raise "native Qt loop starved the Ruby ticker" unless @original || responsive

        { workload: "qt_exec_ruby_thread_progress", original_binding: @original,
          duration_ms: elapsed, iterations: @gaps.length, maximum_gap_ms: maximum,
          responsive:, gaps_ms: @gaps.freeze, environment: Environment.capture }
      end

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  controls = { original: false, xvfb: false }
  OptionParser.new do |options|
    options.on("--original") { controls[:original] = true }
    options.on("--qt-xvfb") { controls[:xvfb] = true }
  end.parse!
  Roded::Benchmarking::Isolation.run(xvfb: controls[:xvfb]) do
    puts JSON.pretty_generate(Roded::Benchmarking::QtEventLoopProbe.new(original: controls[:original]).run)
  end
end
