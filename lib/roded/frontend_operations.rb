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

      return if ui_update_deferred?(update)

      update = with_editor_snapshot(update)
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

    def with_editor_snapshot(update)
      return update unless update.type == :render && current_window

      UIUpdate.new(:render, update.payload.merge(editor_snapshot: editor_snapshot).freeze)
    end

    def ui_update_deferred?(update)
      return false unless @ui_batch_depth.to_i.positive? && %i[render move_cursor].include?(update.type)

      @pending_ui_render = true
      @pending_ui_force_redraw ||= update.payload[:force_redraw]
      true
    end

    def batch_ui_updates
      @ui_batch_depth = @ui_batch_depth.to_i + 1
      yield
      completed = true
    ensure
      @ui_batch_depth -= 1
      finish_ui_batch(completed) if @ui_batch_depth.zero?
    end

    def finish_ui_batch(completed)
      pending = @pending_ui_render
      payload = @pending_ui_force_redraw ? { force_redraw: true } : {}
      @pending_ui_render = false
      @pending_ui_force_redraw = false
      publish_ui_update(UIUpdate.new(:render, payload)) if completed && pending && !@stop_requested
    end

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
