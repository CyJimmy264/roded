module Roded
  # Selects buffers in a view and provides immutable buffer-list access.
  module BufferNavigationOperations
    def buffers = session.buffers

    def next_buffer
      activate_relative_buffer(1)
    end

    def previous_buffer
      activate_relative_buffer(-1)
    end

    def switch_buffer(name)
      buffer = buffers.find { |candidate| candidate.name == name || candidate.filename == name }
      return display_message("No buffer named '#{name}'.") unless buffer

      activate_buffer(buffer, message: "Switched to '#{name}'.")
    end

    def page_size
      active_page_size || frontend_page_size
    end

    def active_page_size
      return unless @active_page_size && current_window&.object_id == @active_page_window_id

      @active_page_size
    end

    def frontend_page_size
      return 1 if @frontends.empty?

      frontend = active_frontend
      return 1 unless frontend.respond_to?(:page_size)

      [frontend.page_size(current_window&.object_id).to_i, 1].max
    end

    private

    def activate_relative_buffer(direction)
      return if buffers.empty?

      available_buffers = buffers
      index = available_buffers.index(current_buffer) || 0
      activate_buffer(available_buffers[(index + direction) % available_buffers.length])
    end

    def active_frontend
      @frontends.find { |candidate| @frontend_sources[candidate] == @active_source_id } || @frontends.first
    end

    def activate_loaded_file(result)
      buffer = Buffer.new(result.path)
      buffer.load_text(result.content)
      buffer.filename = result.path
      buffer.file_revision = result.revision
      add_buffer(buffer)
      update_active_view(buffer)
      display_message("File '#{result.path}' opened.")
    end

    def activate_buffer(buffer, message: nil)
      update_active_view(buffer)
      display_message(message) if message
    end

    def update_active_view(buffer)
      add_window(Window.new(buffer)) unless current_window
      current_window.buffer = buffer if current_window
      buffer.cursor_pos = current_window.point if current_window
      publish_ui_update(UIUpdate.new(:render, {}))
    end
  end
end
