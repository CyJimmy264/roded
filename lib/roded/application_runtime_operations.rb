module Roded
  # Owns event-loop startup, frontend readers, and shutdown cleanup.
  module ApplicationRuntimeOperations
    def run(manage_signals: true)
      trap_signals if manage_signals
      start_frontend_threads
      main_loop
    ensure
      restore_signals if manage_signals
      @stop_requested = true
      shutdown_syntax_highlighting
      shutdown_frontends
      shutdown_ruby_repl
    end

    private

    def main_loop
      @core_thread = Thread.current
      until @stop_requested
        event = @event_queue.pop
        break unless event

        logger.debug("main_loop: event received: #{event.type} #{event.payload.inspect if event.respond_to?(:payload)}")
        handle_event(event)
      end
    rescue StandardError => e
      logger.error("Editor runtime failed: #{e.class}: #{e.message}")
      raise
    end

    def start_frontend_threads
      @frontends.each do |frontend|
        source_id = @frontend_sources.fetch(frontend)
        @frontend_threads << Thread.new { read_frontend_events(frontend, source_id) }
      end
    end

    def read_frontend_events(frontend, source_id)
      loop { break unless read_and_push_frontend_event(frontend, source_id) }
    rescue StandardError => e
      push_event(Event.new(:frontend_failure, { error: e, source_id: }))
    end

    def read_and_push_frontend_event(frontend, source_id)
      event = frontend.next_event
      return push_event(Event.new(:frontend_eof, { frontend: frontend.class.name })) && false unless event

      push_event(Event.new(event.type, event.payload.merge(source_id:)))
      !Application::SYSTEM_EVENTS.include?(event.type)
    end

    def initialize_lifecycle
      @stop_requested = false
      @signal_handlers = {}
    end

    def shutdown_frontends
      notify_frontends_of_shutdown
      @frontend_threads.each(&:join)
      close_frontends
    ensure
      @event_queue.close unless @event_queue.closed?
    end

    def notify_frontends_of_shutdown
      @frontends.each do |frontend|
        frontend.handle_command(UIUpdate.new(:quit, {}))
      rescue StandardError => e
        logger.warn("Frontend shutdown notification failed: #{e.class}: #{e.message}")
      end
    end

    def close_frontends
      @frontends.each do |frontend|
        frontend.close if frontend.respond_to?(:close)
      rescue StandardError => e
        logger.warn("Frontend close failed: #{e.class}: #{e.message}")
      end
    end
  end
end
