module Roded
  # Maps view-owned positions across edits and whole-buffer reloads.
  module WindowPositionOperations
    def transform_positions(change)
      @point = transform_position(@point, change)
      @mark = transform_position(@mark, change) if @mark
      @highlight = nil
      clamp_point
      clamp_mark
      remember_position
    end

    def buffer_edited(buffer, change)
      if buffer.equal?(@buffer)
        transform_positions(change)
      elsif @position_memory.key?(buffer)
        point, mark = @position_memory.fetch(buffer)
        transformed_mark = mark && transform_position(mark, change)
        @position_memory[buffer] = [transform_position(point, change), transformed_mark]
      end
    end

    def buffer_reloaded(buffer)
      if buffer.equal?(@buffer)
        self.point = { row: 0, col: 0 }
        self.mark = nil
        self.top_line = 0
        self.left_column = 0
      elsif @position_memory.key?(buffer)
        @position_memory[buffer] = [{ row: 0, col: 0 }, nil]
      end
    end

    private

    def normalize_highlight_position(position)
      row = position.fetch(:row, 0).to_i.clamp(0, @buffer.lines.length - 1)
      col = position.fetch(:col, 0).to_i.clamp(0, @buffer.lines[row].length)
      { row:, col: }
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
      return map_position_on_replaced_row(position, change) if position[:row] == change.old_end[:row]

      { row: position[:row] + row_delta, col: position[:col] }
    end

    def map_position_on_replaced_row(position, change)
      { row: change.new_end[:row], col: change.new_end[:col] + position[:col] - change.old_end[:col] }
    end
  end
end
