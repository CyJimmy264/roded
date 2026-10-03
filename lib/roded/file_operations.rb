module Roded
  # Owns file loading, saving, revision checks, and overwrite prompts.
  module FileOperations
    def open_file(filename)
      identity = file_service.path_identity(filename)
      existing_buffer = buffers.find { |buffer| buffer.filename == identity }
      return activate_buffer(existing_buffer, message: "File '#{identity}' is already open.") if existing_buffer

      result = File.file?(identity) ? file_service.read(identity) : file_service.create_new(identity)
      activate_loaded_file(result)
    rescue Errno::ENOENT
      display_message("File not found: #{filename}")
    rescue StandardError => e
      display_message("Error opening file: #{e.message}")
    end

    def save_file(filename, overwrite: false)
      buffer = current_buffer
      return unless buffer

      save_buffer_document(buffer, filename, overwrite:)
    end

    def save_buffer_document(buffer, filename, overwrite: false)
      return ask_before_overwrite(buffer, filename) if !overwrite && overwrite_confirmation_needed?(buffer, filename)

      write_saved_buffer(buffer, filename, overwrite)
    rescue FileService::Conflict => e
      request_disk_conflict_resolution(buffer, filename, e.message)
      false
    rescue StandardError => e
      display_message("Error saving file: #{e.message}")
      false
    end

    def clear_pending_save_confirmation
      @pending_save_confirmation = nil
    end

    def pending_save_confirmation?
      !@pending_save_confirmation.nil?
    end

    def handle_overwrite_confirmation(response)
      pending = @pending_save_confirmation
      return unless pending

      return handle_disk_conflict_response(pending, response) if pending[:disk_conflict]

      case response.to_s.strip.downcase
      when "y", "yes", "overwrite" then overwrite_pending_save(pending)
      when "n", "no", "c", "cancel", "" then cancel_pending_save
      else
        display_message("Choose yes to overwrite or no to cancel.")
        start_minibuffer(:overwrite_confirmation, "Overwrite file? (y/n) ")
      end
    end

    private

    def overwrite_confirmation_needed?(buffer, filename)
      same_file = buffer.filename && file_service.path_identity(filename) == buffer.filename
      !same_file && (File.exist?(filename) || File.symlink?(filename))
    end

    def request_overwrite_confirmation(buffer, filename, prompt)
      @pending_save_confirmation = { buffer:, filename: }
      start_minibuffer(:overwrite_confirmation, prompt)
    end

    def ask_before_overwrite(buffer, filename)
      request_overwrite_confirmation(buffer, filename, "Overwrite existing file '#{filename}'? (y/n) ")
      :prompted
    end

    def write_saved_buffer(buffer, filename, overwrite)
      result = write_buffer(buffer, filename, overwrite:)
      buffer.filename = result.path
      buffer.file_revision = result.revision
      buffer.mark_saved
      display_message("File '#{result.path}' saved.")
      result
    end

    def overwrite_pending_save(pending)
      @pending_save_confirmation = nil
      saved = save_buffer_document(pending.fetch(:buffer), pending.fetch(:filename), overwrite: true)
      save_next_close_buffer if saved && pending_close_action?
    end

    def cancel_pending_save
      @pending_save_confirmation = nil
      pending_close_action? ? cancel_pending_close : display_message("Save cancelled.")
    end

    def file_service
      @file_service ||= FileService.new
    end

    def write_buffer(buffer, filename, overwrite: false)
      expected_revision = overwrite ? nil : file_revision_for(buffer, filename)
      file_service.write(filename, buffer.to_s, expected_revision:)
    end

    def file_revision_for(buffer, filename)
      same_file = buffer.filename && file_service.path_identity(filename) == buffer.filename
      return buffer.file_revision if same_file
      return if File.exist?(filename) || File.symlink?(filename)

      FileService::ABSENT_REVISION
    end
  end
end
