module Roded
  # Keeps frontends and views consistent after removing a buffer.
  module CloseBufferRemoval
    private

    def unregister_frontends(buffer)
      @frontends.each { |frontend| frontend.remove_buffer(buffer) if frontend.respond_to?(:remove_buffer) }
    end

    def preserve_writable_buffer
      add_buffer(Buffer.new("*scratch*")) if buffers.empty?
    end

    def replace_closed_buffer_views(buffer)
      windows.each do |window|
        window.buffer = buffers.first if window.buffer.equal?(buffer)
        window.forget_buffer(buffer)
      end
    end

    def render_buffer_removal
      publish_ui_update(UIUpdate.new(:render, {}))
    end
  end

  # Coordinates save/discard/cancel when a modified buffer or editor is closed.
  module CloseOperations
    include CloseBufferRemoval

    def kill_current_buffer
      buffer = current_buffer
      return unless buffer

      buffer.modified? ? begin_close_action(:kill, [buffer]) : remove_buffer(buffer)
    end

    def request_quit(force: false)
      return if @stop_requested
      return force_quit if force
      return if pending_close_action?

      dirty_buffers = buffers.select(&:modified?)
      return finish_quit if dirty_buffers.empty?

      begin_close_action(:quit, dirty_buffers)
    end

    def handle_close_prompt(kind, response)
      case kind
      when :close_confirmation then handle_close_confirmation(response)
      when :close_save_as then save_pending_close_buffer(response)
      end
    end

    def clear_pending_close_state
      @pending_close_action = nil
      @pending_close_buffers = []
      @pending_save_buffer = nil
    end

    def pending_close_action?
      !@pending_close_action.nil?
    end

    private

    def begin_close_action(kind, dirty_buffers)
      @pending_close_action = { kind:, buffer: current_buffer }
      @pending_close_buffers = dirty_buffers.dup
      start_minibuffer(:close_confirmation, "Unsaved changes: save, discard, or cancel? (s/d/c) ")
    end

    def handle_close_confirmation(response)
      case response.to_s.strip.downcase
      when "s", "save" then save_next_close_buffer
      when "d", "discard" then finish_pending_close
      when "c", "cancel", "" then cancel_minibuffer
      else
        display_message("Choose save, discard, or cancel.")
        start_minibuffer(:close_confirmation, "Unsaved changes: save, discard, or cancel? (s/d/c) ")
      end
    end

    def save_next_close_buffer
      buffer = @pending_close_buffers.shift
      return finish_pending_close unless buffer
      return continue_close_after_save(buffer, buffer.filename) if buffer.filename

      @pending_save_buffer = buffer
      start_minibuffer(:close_save_as, "Save #{buffer.name || "buffer"} as: ")
    end

    def save_pending_close_buffer(filename)
      return cancel_pending_close if filename.to_s.empty?

      buffer = @pending_save_buffer
      @pending_save_buffer = nil
      continue_close_after_save(buffer, filename)
    end

    def continue_close_after_save(buffer, filename)
      saved = save_buffer_document(buffer, filename)
      return if pending_save_confirmation?
      return cancel_pending_close unless saved

      save_next_close_buffer
    end

    def finish_pending_close
      action = @pending_close_action
      clear_pending_close_state
      action[:kind] == :kill ? remove_buffer(action[:buffer]) : finish_quit
    end

    def cancel_pending_close
      clear_pending_close_state
      clear_pending_save_confirmation
      @focus = :buffer
      broadcast_focus
      publish_ui_update(UIUpdate.new(:minibuffer_clear, {}))
      publish_ui_update(UIUpdate.new(:render, {}))
    end

    def remove_buffer(buffer)
      session.remove_buffer(buffer)
      unregister_frontends(buffer)
      preserve_writable_buffer
      replace_closed_buffer_views(buffer)
      render_buffer_removal
      display_message("Buffer killed.")
    end

    def force_quit
      clear_pending_close_state
      clear_pending_save_confirmation
      finish_quit
    end

    def finish_quit
      @stop_requested = true
      publish_ui_update(UIUpdate.new(:quit, {}))
    end
  end
end
