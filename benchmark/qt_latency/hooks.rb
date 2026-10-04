module Roded
  module Benchmarking
    # Attaches phase timestamps only to the benchmark's own editor instances.
    module LatencyHooks
      def instrument(application, frontend, trace)
        instrument_input(frontend, trace)
        instrument_core(application, frontend, trace)
        wrap(frontend.view, :render_layout) do |snapshot, original|
          trace.widget_started(snapshot)
          original.call(snapshot)
          trace.rendered(snapshot)
        end
      end

      def instrument_input(frontend, trace)
        translator = Frontends::QtKeyTranslator.new
        wrap(frontend.instance_variable_get(:@input_router), :enqueue_key) do |payload, original|
          key = translator.translate(payload)
          trace.key_received(key) if key && !%w[C-x C-c].include?(key)
          original.call(payload)
        end
      end

      def instrument_core(application, frontend, trace)
        wrap(application, :handle_event) do |event, original|
          with_key_trace(event, trace) { original.call(event) }
        end
        wrap(frontend, :handle_command) do |command, original|
          if command.type == :render && Thread.current[:roded_latency_key]
            trace.snapshot_posted(command.payload.fetch(:editor_snapshot))
          end
          original.call(command)
        end
      end

      def with_key_trace(event, trace)
        Thread.current[:roded_latency_key] = event.type == :key
        trace.mark(:core_started) if event.type == :key
        yield
      ensure
        Thread.current[:roded_latency_key] = nil
      end

      def wrap(object, name, &callback)
        original = object.method(name)
        object.define_singleton_method(name) { |argument| callback.call(argument, original) }
      end
    end
  end
end
