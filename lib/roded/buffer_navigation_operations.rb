module Roded
  # Selects buffers in a view and provides immutable buffer-list access.
  module BufferNavigationOperations
    def current_buffer
      @current_window&.buffer || @current_buffer || @buffers.first
    end

    def buffers
      @buffers.dup.freeze
    end

    def next_buffer
      activate_relative_buffer(1)
    end

    def previous_buffer
      activate_relative_buffer(-1)
    end

    def switch_buffer(name)
      buffer = @buffers.find { |candidate| candidate.name == name || candidate.filename == name }
      return display_message("No buffer named '#{name}'.") unless buffer

      activate_buffer(buffer, message: "Switched to '#{name}'.")
    end

    def page_size
      return @active_page_size if @active_page_size
      return 1 if @frontends.empty?

      frontend = @frontends.find { |candidate| @frontend_sources[candidate] == @active_source_id }
      frontend ||= @frontends.first
      return 1 unless frontend.respond_to?(:page_size)

      [frontend.page_size(current_window&.object_id).to_i, 1].max
    end

    private

    def activate_relative_buffer(direction)
      return if @buffers.empty?

      index = @buffers.index(current_buffer) || 0
      activate_buffer(@buffers[(index + direction) % @buffers.length])
    end

    def activate_loaded_file(result)
      buffer = Buffer.new(result.path)
      buffer.load_text(result.content)
      buffer.filename = result.path
      buffer.file_revision = result.revision
      add_buffer(buffer)
      @current_buffer = buffer
      update_active_view(buffer)
      display_message("File '#{result.path}' opened.")
    end

    def activate_buffer(buffer, message: nil)
      @current_buffer = buffer
      update_active_view(buffer)
      display_message(message) if message
    end

    def update_active_view(buffer)
      @current_window.buffer = buffer if @current_window
      buffer.cursor_pos = @current_window.point if @current_window
      @frontends.each { |frontend| frontend.render(buffer) }
      broadcast_command(Command.new(:render, {}))
    end
  end
end
