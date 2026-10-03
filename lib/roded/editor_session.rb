module Roded
  # Owns the documents and logical window tree for one editor instance.
  class EditorSession
    attr_accessor :current_window, :window_layout

    def initialize
      @buffers = []
      @current_window = nil
      @window_layout = nil
    end

    def buffers = @buffers.dup.freeze

    def add_buffer(buffer)
      @buffers << buffer
    end

    def remove_buffer(buffer)
      @buffers.delete(buffer)
    end
  end
end
