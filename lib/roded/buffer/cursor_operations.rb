module Roded
  # Owns buffer cursor positions and their movement constraints.
  module BufferCursorOperations
    def cursor_pos=(position)
      next_position = { row: position.fetch(:row, 0).to_i, col: position.fetch(:col, 0).to_i }
      break_typing_undo_group if @cursor_pos != next_position
      @cursor_pos = next_position
      clamp_cursor
    end

    def cursor_pos
      @cursor_pos.dup.freeze
    end

    def line_at_cursor
      @lines[@cursor_pos[:row]].dup.freeze
    end

    def cursor_row = @cursor_pos[:row]

    def cursor_col = @cursor_pos[:col]

    def move_cursor_left
      break_typing_undo_group
      @cursor_pos[:col] = [@cursor_pos[:col] - 1, 0].max
      notify_observers
    end

    def move_cursor_right
      break_typing_undo_group
      @cursor_pos[:col] = [@cursor_pos[:col] + 1, line_at_cursor.length].min
      notify_observers
    end

    def move_cursor_line_start
      break_typing_undo_group
      @cursor_pos[:col] = 0
      notify_observers
    end

    def move_cursor_line_end
      break_typing_undo_group
      @cursor_pos[:col] = line_at_cursor.length
      notify_observers
    end

    def move_cursor_document_start
      move_cursor_to_offset(0)
    end

    def move_cursor_document_end
      move_cursor_to_offset(@lines.join("\n").length)
    end

    def move_cursor_word_forward
      chars = @lines.join("\n").each_char.to_a
      offset = cursor_offset
      offset += 1 while offset < chars.length && !word_character?(chars[offset])
      offset += 1 while offset < chars.length && word_character?(chars[offset])
      move_cursor_to_offset(offset)
    end

    def move_cursor_word_backward
      chars = @lines.join("\n").each_char.to_a
      offset = cursor_offset
      offset -= 1 while offset.positive? && !word_character?(chars[offset - 1])
      offset -= 1 while offset.positive? && word_character?(chars[offset - 1])
      move_cursor_to_offset(offset)
    end

    def move_cursor_up
      break_typing_undo_group
      @cursor_pos[:row] = [@cursor_pos[:row] - 1, 0].max
      clamp_cursor_col
      notify_observers
    end

    def move_cursor_down
      break_typing_undo_group
      @cursor_pos[:row] = [@cursor_pos[:row] + 1, @lines.length - 1].min
      clamp_cursor_col
      notify_observers
    end

    def move_cursor_page_up(page_size)
      move_cursor_by_page(-page_size.to_i)
    end

    def move_cursor_page_down(page_size)
      move_cursor_by_page(page_size.to_i)
    end

    private

    def cursor_offset
      @lines.take(@cursor_pos[:row]).sum(&:length) + @cursor_pos[:row] + @cursor_pos[:col]
    end

    def move_cursor_to_offset(offset)
      break_typing_undo_group
      chars = @lines.join("\n").each_char.to_a
      @cursor_pos = position_at_offset(0, chars, offset.clamp(0, chars.length)).dup
      clamp_cursor
      notify_observers
    end

    def word_character?(character)
      character&.match?(/\A[\p{Alnum}_]\z/)
    end

    def move_cursor_by_page(delta)
      break_typing_undo_group
      @cursor_pos[:row] = [@cursor_pos[:row] + delta, 0].max
      @cursor_pos[:row] = [@cursor_pos[:row], @lines.length - 1].min
      clamp_cursor_col
      notify_observers
    end

    def clamp_cursor_col
      @cursor_pos[:col] = [@cursor_pos[:col], line_at_cursor.length].min
    end

    def clamp_cursor
      @cursor_pos[:row] = @cursor_pos[:row].to_i.clamp(0, @lines.length - 1)
      clamp_cursor_col
    end
  end
end
