module Roded
  # Connects frontend adapters to core state and broadcasts immutable updates.
  module FrontendOperations
    def add_frontend(frontend)
      @frontends << frontend
      register_frontend_source(frontend)
      prepare_frontend(frontend)
      sync_frontend(frontend)
    end

    def broadcast_command(command)
      if command.type == :render && current_window
        payload = command.payload.merge(editor_snapshot: editor_snapshot)
        command = Command.new(:render, payload.freeze)
      end
      logger.debug("broadcast_command: #{command.type}")
      @frontends.each { |frontend| frontend.handle_command(command) }
    end

    def push_event(event)
      @event_queue << event
    rescue ClosedQueueError
      nil
    end

    private

    def register_frontend_source(frontend)
      source_id = frontend.respond_to?(:input_source_id) ? frontend.input_source_id : frontend.object_id
      @frontend_sources[frontend] = source_id
    end

    def prepare_frontend(frontend)
      frontend.keymap = @keymap if frontend.respond_to?(:keymap=)
      frontend.focus = @focus if frontend.respond_to?(:focus=)
      @buffers.each { |buffer| frontend.add_buffer(buffer) }
    end

    def sync_frontend(frontend)
      frontend.render(current_buffer) if current_buffer && frontend.respond_to?(:render)
      return unless @focus == :minibuffer && frontend.respond_to?(:handle_command)

      frontend.handle_command(Command.new(:minibuffer_render, minibuffer_snapshot))
    end

    def minibuffer_snapshot
      { prompt: @minibuffer.prompt, text: @minibuffer.text, cursor: @minibuffer.cursor }
    end

    def display_message(message)
      @frontends.each do |frontend|
        frontend.display_message(message) if frontend.respond_to?(:display_message)
      end
    end

    def broadcast_focus
      @frontends.each do |frontend|
        frontend.focus = @focus if frontend.respond_to?(:focus=)
      end
    end
  end
end
