module Roded
  # Provides point movement for a single view over a shared buffer.
  module WindowCursorOperations
    def line_at_point
      @buffer.lines[@point[:row]]
    end

    def move_cursor_left
      prepare_cursor_movement
      @point[:col] = [@point[:col] - 1, 0].max
      remember_position
    end

    def move_cursor_right
      prepare_cursor_movement
      @point[:col] = [@point[:col] + 1, line_at_point.length].min
      remember_position
    end

    def move_cursor_line_start
      prepare_cursor_movement
      @point[:col] = 0
      remember_position
    end

    def move_cursor_line_end
      prepare_cursor_movement
      @point[:col] = line_at_point.length
      remember_position
    end

    def move_cursor_document_start
      prepare_cursor_movement
      self.point = { row: 0, col: 0 }
    end

    def move_cursor_document_end
      prepare_cursor_movement
      lines = @buffer.lines
      self.point = { row: lines.length - 1, col: lines.last.length }
    end

    def move_cursor_word_forward
      prepare_cursor_movement
      self.point = forward_word_position
    end

    def move_cursor_word_backward
      prepare_cursor_movement
      self.point = backward_word_position
    end

    def move_cursor_up
      prepare_cursor_movement
      @point[:row] = [@point[:row] - 1, 0].max
      clamp_point
      remember_position
    end

    def move_cursor_down
      prepare_cursor_movement
      @point[:row] = [@point[:row] + 1, @buffer.lines.length - 1].min
      clamp_point
      remember_position
    end

    def move_cursor_page_up(page_size)
      move_cursor_by_page(-page_size.to_i)
    end

    def move_cursor_page_down(page_size)
      move_cursor_by_page(page_size.to_i)
    end

    private

    def prepare_cursor_movement
      @buffer.break_typing_undo_group
      @highlight = nil
    end

    def forward_word_position
      lines = @buffer.lines
      row, col = @point.values_at(:row, :col)
      while row < lines.length
        match = /[\p{Alnum}_]+/.match(lines[row], col)
        return { row:, col: match.end(0) } if match

        row += 1
        col = 0
      end
      { row: lines.length - 1, col: lines.last.length }
    end

    def backward_word_position
      lines = @buffer.lines
      row, col = @point.values_at(:row, :col)
      while row >= 0
        match = /[\p{Alnum}_]+[^\p{Alnum}_]*\z/.match(lines[row][0, col])
        return { row:, col: match.begin(0) } if match

        row -= 1
        col = lines[row].length if row >= 0
      end
      { row: 0, col: 0 }
    end

    def move_cursor_by_page(delta)
      prepare_cursor_movement
      @point[:row] = (@point[:row] + delta).clamp(0, @buffer.lines.length - 1)
      clamp_point
      remember_position
    end
  end
end
