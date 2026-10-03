require_relative "window/cursor_operations"
require_relative "window/position_operations"

module Roded
  # A view over a buffer with independent cursor, mark, and viewport state.
  class Window
    include WindowCursorOperations
    include WindowPositionOperations

    attr_reader :buffer
    attr_accessor :top_line, :left_column

    def initialize(buffer)
      @buffer = buffer
      @point = { row: 0, col: 0 }
      @mark = nil
      @highlight = nil
      @top_line = 0
      @left_column = 0
      @position_memory = {}.compare_by_identity
      @position_memory[buffer] = [@point.dup, nil]
      buffer.add_edit_observer(self)
    end

    def buffer=(buffer)
      remember_position
      @buffer = buffer
      @buffer.add_edit_observer(self)
      restore_buffer_position
    end

    def forget_buffer(buffer)
      return if buffer.equal?(@buffer)

      buffer.remove_edit_observer(self)
      @position_memory.delete(buffer)
    end

    def point=(position)
      @point = { row: position.fetch(:row, 0).to_i, col: position.fetch(:col, 0).to_i }
      @highlight = nil
      clamp_point
      remember_position
    end

    def point
      @point.dup.freeze
    end

    def mark=(position)
      @mark = position && { row: position.fetch(:row, 0).to_i, col: position.fetch(:col, 0).to_i }
      clamp_mark
      remember_position
    end

    def mark
      @mark&.dup&.freeze
    end

    def highlight=(range)
      @highlight = if range
                     {
                       start: normalize_highlight_position(range.fetch(:start)),
                       finish: normalize_highlight_position(range.fetch(:finish))
                     }
                   end
    end

    def highlight = @highlight&.transform_values { |position| position.dup.freeze }&.freeze

    def copy
      window = self.class.new(@buffer)
      window.point = @point
      window.mark = @mark
      window.top_line = @top_line
      window.left_column = @left_column
      window
    end

    private

    def remember_position
      @position_memory[@buffer] = [@point.dup, @mark&.dup]
    end

    def restore_buffer_position
      @point, @mark = @position_memory.fetch(@buffer, [{ row: 0, col: 0 }, nil])
      @point = @point.dup
      @mark = @mark&.dup
      @highlight = nil
      clamp_point
      clamp_mark
    end
  end
end
