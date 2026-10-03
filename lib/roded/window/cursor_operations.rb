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
      move_cursor_to_offset(0)
    end

    def move_cursor_document_end
      move_cursor_to_offset(@buffer.lines.join("\n").length)
    end

    def move_cursor_word_forward
      chars = @buffer.lines.join("\n").each_char.to_a
      offset = cursor_offset
      offset += 1 while offset < chars.length && !word_character?(chars[offset])
      offset += 1 while offset < chars.length && word_character?(chars[offset])
      move_cursor_to_offset(offset)
    end

    def move_cursor_word_backward
      chars = @buffer.lines.join("\n").each_char.to_a
      offset = cursor_offset
      offset -= 1 while offset.positive? && !word_character?(chars[offset - 1])
      offset -= 1 while offset.positive? && word_character?(chars[offset - 1])
      move_cursor_to_offset(offset)
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

    def cursor_offset
      @buffer.lines.take(@point[:row]).sum(&:length) + @point[:row] + @point[:col]
    end

    def move_cursor_to_offset(offset)
      prepare_cursor_movement
      chars = @buffer.lines.join("\n").each_char.to_a
      @point = position_at_offset(chars, offset.clamp(0, chars.length))
      clamp_point
      remember_position
    end

    def position_at_offset(chars, offset)
      preceding = chars.take(offset).join
      parts = preceding.split("\n", -1)
      parts = [""] if parts.empty?
      { row: parts.length - 1, col: parts.last.length }
    end

    def word_character?(character)
      character&.match?(/\A[\p{Alnum}_]\z/)
    end

    def move_cursor_by_page(delta)
      prepare_cursor_movement
      @point[:row] = (@point[:row] + delta).clamp(0, @buffer.lines.length - 1)
      clamp_point
      remember_position
    end
  end
end
