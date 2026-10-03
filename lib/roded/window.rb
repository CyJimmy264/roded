module Roded
  # A view over a buffer with independent cursor, mark, and viewport state.
  class Window
    attr_reader :buffer
    attr_accessor :top_line, :left_column

    def initialize(buffer)
      @buffer = buffer
      @point = buffer.cursor_pos.dup
      @mark = nil
      @highlight = nil
      @top_line = 0
      @left_column = 0
      @position_memory = {}.compare_by_identity
      @position_memory[buffer] = [@point.dup, nil]
    end

    def buffer=(buffer)
      remember_position
      @buffer = buffer
      point, mark = @position_memory.fetch(buffer) do
        [buffer.cursor_pos.dup, nil]
      end
      @point = point.dup
      @mark = mark&.dup
      @highlight = nil
      clamp_point
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

    def transform_positions(change)
      @point = transform_position(@point, change)
      @mark = transform_position(@mark, change) if @mark
      @highlight = nil
      clamp_point
      clamp_mark
      remember_position
    end

    private

    def normalize_highlight_position(position)
      row = position.fetch(:row, 0).to_i.clamp(0, @buffer.lines.length - 1)
      col = position.fetch(:col, 0).to_i.clamp(0, @buffer.lines[row].length)
      { row:, col: }
    end

    def remember_position
      @position_memory[@buffer] = [@point.dup, @mark&.dup]
    end

    def clamp_point
      @point[:row] = @point[:row].clamp(0, @buffer.lines.length - 1)
      @point[:col] = @point[:col].clamp(0, @buffer.lines[@point[:row]].length)
    end

    def clamp_mark
      return unless @mark

      @mark[:row] = @mark[:row].clamp(0, @buffer.lines.length - 1)
      @mark[:col] = @mark[:col].clamp(0, @buffer.lines[@mark[:row]].length)
    end

    def transform_position(position, change)
      return position if position_before?(position, change.start)
      return change.new_end.dup if position_before?(position, change.old_end)

      map_position_after_edit(position, change)
    end

    def position_before?(position, other)
      (position[:row] <=> other[:row]).negative? ||
        (position[:row] == other[:row] && position[:col] < other[:col])
    end

    def map_position_after_edit(position, change)
      row_delta = change.new_end[:row] - change.old_end[:row]
      if position[:row] == change.old_end[:row]
        return { row: change.new_end[:row],
                 col: change.new_end[:col] + position[:col] - change.old_end[:col] }
      end

      { row: position[:row] + row_delta, col: position[:col] }
    end
  end
end
