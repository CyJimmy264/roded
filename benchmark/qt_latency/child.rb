if $PROGRAM_NAME == __FILE__ && ENV["RODED_KEY_LATENCY_XVFB"] != "1"
  abort "Run benchmark/qt_key_latency.rb to create a private Xvfb session"
end

require_relative "../../lib/roded"
require_relative "../../lib/roded/frontends/qt"
require_relative "../roded/fixture"
require_relative "../roded/isolation"
require_relative "trace"
require_relative "hooks"
require "json"

module Roded
  module Benchmarking
    # Runs the real frontend/core loops, with the production 12 ms dispatcher.
    class LatencyChild
      include LatencyHooks

      def run(lines:, profile:)
        fixture = Fixture.new(line_count: lines, profile:)
        application = build_application(fixture)
        frontend = Frontends::Qt.new(application)
        application.add_frontend(frontend)
        trace = LatencyTrace.new(frontend)
        instrument(application, frontend, trace)
        ready_timer(frontend, application, trace)
        run_frontend(frontend, application)
      end

      private

      def run_frontend(frontend, application)
        @shutdown_reader = Thread.new { application.push_event(InputEvent.new(:quit, {})) if $stdin.gets }
        frontend.run
      ensure
        @shutdown_reader&.kill
        @shutdown_reader&.join
      end

      def build_application(fixture)
        application = Application.new
        buffer = Buffer.new("latency-#{fixture.profile}")
        buffer.major_mode = fixture.mode
        buffer.load_text(fixture.text)
        application.add_buffer(buffer)
        application.add_window(Window.new(buffer))
        position(application.current_window, fixture.line_count)
        application
      end

      def position(window, lines)
        window.point = { row: lines / 2, col: 4 }
        window.top_line = window.point[:row] - 10
      end

      def ready_timer(frontend, application, trace)
        @timer = QTimer.new
        @timer.set_interval(200)
        @timer.connect("timeout") do
          @timer.stop
          frontend.view.editor.set_focus
          trace.emit("ready", application.editor_snapshot)
        end
        @timer.start
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  Roded::Frontends::QtEventLoop.define_singleton_method(:run, &:exec) if ARGV.include?("--original")
  Roded::Benchmarking::Isolation.run(xvfb: true) do
    Roded::Benchmarking::LatencyChild.new.run(lines: Integer(ARGV.fetch(0)), profile: ARGV.fetch(1))
  end
end
