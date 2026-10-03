module Roded
  # Resolves disk conflicts by reloading, overwriting, or preserving local edits.
  module FileReloadOperations
    private

    def request_disk_conflict_resolution(buffer, filename, message)
      @pending_save_confirmation = { buffer:, filename:, disk_conflict: true }
      start_minibuffer(:overwrite_confirmation, "#{message}. Reload, overwrite, or cancel? (r/o/c) ")
    end

    def handle_disk_conflict_response(pending, response)
      case response.to_s.strip.downcase
      when "r", "reload" then reload_conflicting_buffer(pending)
      when "o", "overwrite" then overwrite_pending_save(pending)
      when "c", "cancel", "" then cancel_pending_save
      else
        display_message("Choose reload, overwrite, or cancel.")
        start_minibuffer(:overwrite_confirmation, "Reload, overwrite, or cancel? (r/o/c) ")
      end
    end

    def reload_conflicting_buffer(pending)
      result = file_service.read(pending.fetch(:filename))
      finish_reload(pending, result)
    rescue StandardError => e
      @pending_save_confirmation = nil
      display_message("Error reloading file: #{e.message}")
      cancel_pending_close if pending_close_action?
    ensure
      publish_ui_update(UIUpdate.new(:render, {}))
    end

    def finish_reload(pending, result)
      apply_reloaded_file(pending.fetch(:buffer), result)
      display_message("File '#{result.path}' reloaded.")
      @pending_save_confirmation = nil
      save_next_close_buffer if pending_close_action?
    end

    def apply_reloaded_file(buffer, result)
      buffer.load_text(result.content)
      buffer.file_revision = result.revision
      @windows.each { |window| reset_reloaded_view(window, buffer) }
    end

    def reset_reloaded_view(window, buffer)
      return unless window.buffer.equal?(buffer)

      window.point = buffer.cursor_pos
      window.mark = nil
      window.top_line = 0
      window.left_column = 0
    end
  end
end
