module Roded
  # Keeps logical lines and serialized newline metadata in sync.
  module BufferSerializationOperations
    def lines=(lines)
      return if readonly

      new_lines = Array(lines).map(&:to_s)
      new_lines = [""] if new_lines.empty?
      record_edit(0, @lines.length, new_lines.length) { @lines = new_lines }
    end

    def load_text(text)
      validate_text!(text)
      @line_ending = text.scan(/\r\n|\n/).uniq.first || "\n"
      @final_newline = text.end_with?("\n")
      @lines = text.gsub("\r\n", "\n").split("\n", -1)
      @lines = [""] if @lines.empty?
      reset_edit_history
      @edit_observers.each { |observer| observer.buffer_reloaded(self) if observer.respond_to?(:buffer_reloaded) }
      mark_saved
      self
    end

    def lines
      @lines.map { |line| line.dup.freeze }.freeze
    end

    def to_s
      @lines.join(@line_ending)
    end

    def modified?
      to_s != @saved_text
    end

    def mark_saved
      @saved_text = to_s
    end

    def final_newline=(value)
      return if readonly

      desired = value ? true : false
      return if desired == @final_newline

      record_edit(0, @lines.length, @lines.length + (desired ? 1 : -1)) do
        desired ? @lines << "" : @lines.pop
      end
    end

    def line_ending=(value)
      raise ArgumentError, "unsupported line ending" unless ["\n", "\r\n"].include?(value)

      return if readonly

      record_edit(0, @lines.length, @lines.length) { @line_ending = value }
    end

    private

    def reset_edit_history
      @undo_stack.clear
      @redo_stack.clear
      @undo_group_edits.clear
      @typing_undo_group = nil
    end

    def sync_final_newline
      @final_newline = @lines.length > 1 && @lines.last.empty?
    end

    def validate_text!(text)
      raise ArgumentError, "text must be valid UTF-8" unless text.encoding == Encoding::UTF_8 && text.valid_encoding?
      raise ArgumentError, "mixed line endings are not supported" if text.scan(/\r\n|\n/).uniq.length > 1
    end
  end
end
