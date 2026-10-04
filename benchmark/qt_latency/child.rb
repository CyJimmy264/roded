if $PROGRAM_NAME == __FILE__ && ENV["RODED_KEY_LATENCY_XVFB"] != "1"
  abort "Run benchmark/qt_key_latency.rb to create a private Xvfb session"
end

require_relative "../../lib/roded"
require_relative "../../lib/roded/frontends/qt"
require_relative "file_fixture"
require_relative "child_documents"
require_relative "../roded/isolation"
require_relative "trace"
require_relative "hooks"
require "json"

module Roded
  module Benchmarking
    # Runs the real frontend/core loops and the production UI dispatcher.
    class LatencyChild
      include LatencyHooks
      include LatencyChildDocuments

      def run(config:)
        @config = config
        fixture = LatencyFileFixture.build(config)
        application = build_application(fixture)
        frontend = Frontends::Qt.new(application)
        set_dispatcher_interval(frontend, config[:dispatcher_ms]) if config[:dispatcher_ms]
        application.add_frontend(frontend)
        trace = LatencyTrace.new(frontend)
        instrument(application, frontend, trace)
        ready_timer(frontend, application, trace)
        run_frontend(frontend, application)
      end

      private

      def run_frontend(frontend, application)
        @shutdown_reader = Thread.new { control_requests(application) }
        frontend.run
      ensure
        @shutdown_reader&.kill
        @shutdown_reader&.join
      end

      def set_dispatcher_interval(frontend, milliseconds)
        frontend.instance_variable_get(:@ui_dispatcher).instance_variable_get(:@timer).set_interval(milliseconds)
      end

      def control_requests(application)
        while (request = $stdin.gets)
          if request.strip == "cpu"
            emit_cpu_sample
          else
            application.push_event(InputEvent.new(:quit, {}))
            break
          end
        end
      end

      def emit_cpu_sample
        puts JSON.generate(type: "cpu", monotonic_ns: Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond),
                           cpu_ns: Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID, :nanosecond))
        $stdout.flush
      end

      def ready_timer(frontend, application, trace)
        @timer = QTimer.new
        @timer.set_interval(200)
        @timer.connect("timeout") do
          @timer.stop
          frontend.view.editor.set_focus
          trace.emit("ready", application.editor_snapshot)
        end
        start_timer_when_shown(frontend.view)
      end

      def start_timer_when_shown(view)
        timer = @timer
        show = view.method(:show)
        width, height = @config.values_at(:width, :height)
        # Initial document construction can exceed the readiness delay.
        view.define_singleton_method(:show) do
          show.call
          window.resize(width, height)
          timer.start
        end
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  Roded::Frontends::QtEventLoop.define_singleton_method(:run, &:exec) if ARGV.include?("--original")
  Roded::Benchmarking::Isolation.run(xvfb: true) do
    config = JSON.parse(ARGV.fetch(0), symbolize_names: true)
    Roded::Benchmarking::LatencyChild.new.run(config:)
  end
end
