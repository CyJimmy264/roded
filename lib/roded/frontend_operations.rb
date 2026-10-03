module Roded
  # Connects frontend adapters to core state and broadcasts immutable updates.
  module FrontendOperations
    def add_frontend(frontend)
      @frontends << frontend
      register_frontend_source(frontend)
      prepare_frontend(frontend)
      sync_frontend(frontend)
    end

    def publish_ui_update(update)
      raise ArgumentError, "expected UIUpdate, got #{update.class}" unless update.is_a?(UIUpdate)

      if update.type == :render && current_window
        payload = update.payload.merge(editor_snapshot: editor_snapshot).freeze
        update = UIUpdate.new(:render, payload)
      end
      logger.debug("publish_ui_update: #{update.type}")
      @frontends.each { |frontend| deliver_ui_update(frontend, update) }
    end

    alias broadcast_command publish_ui_update

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
      buffers.each { |buffer| frontend.add_buffer(buffer) if frontend.respond_to?(:add_buffer) }
    end

    def sync_frontend(frontend)
      if current_buffer
        payload = current_window ? { editor_snapshot: editor_snapshot }.freeze : {}.freeze
        deliver_ui_update(frontend, UIUpdate.new(:render, payload))
      end
      deliver_ui_update(frontend, UIUpdate.new(:focus, { focus: @focus }.freeze))
      return unless @focus == :minibuffer && frontend.respond_to?(:handle_command)

      deliver_ui_update(frontend, UIUpdate.new(:minibuffer_render, minibuffer_snapshot.freeze))
    end

    def minibuffer_snapshot
      { prompt: @minibuffer.prompt, text: @minibuffer.text, cursor: @minibuffer.cursor }
    end

    def display_message(message)
      publish_ui_update(UIUpdate.new(:message, { text: message.to_s.dup.freeze }.freeze))
    end

    def broadcast_focus
      publish_ui_update(UIUpdate.new(:focus, { focus: @focus }.freeze))
    end

    def deliver_ui_update(frontend, update)
      frontend.handle_command(update) if frontend.respond_to?(:handle_command)
    end
  end
end
