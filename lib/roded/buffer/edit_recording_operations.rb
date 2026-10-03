module Roded
  # Captures before/after document fragments and records reversible edits.
  module BufferEditRecordingOperations
    private

    def record_edit(row, before_count, after_count, undo_group: nil)
      break_typing_undo_group if undo_group != :typing && @undo_group_depth.zero?
      before = edit_snapshot(row, before_count)
      yield
      sync_final_newline
      clamp_cursor
      after = edit_snapshot(row, after_count)
      return if before == after

      publish_edit(build_edit(row, before, after), undo_group:)
    end

    def publish_edit(edit, undo_group: nil)
      if @undo_group_depth.positive?
        @undo_group_edits << edit
      elsif undo_group == :typing
        append_typing_edit(edit)
      else
        @undo_stack << [edit]
      end
      @redo_stack.clear
      notify_position_change(edit.position_change)
      notify_observers
    end

    def append_typing_edit(edit)
      previous = @typing_undo_group&.last
      if previous && previous.row == edit.row && previous.after_cursor == edit.before_cursor &&
         previous.after_lines == edit.before_lines
        @typing_undo_group << edit
      else
        @typing_undo_group = [edit]
        @undo_stack << @typing_undo_group
      end
    end

    def edit_snapshot(row, line_count)
      {
        lines: @lines.slice(row, line_count).map(&:dup), cursor: @cursor_pos.dup,
        line_ending: @line_ending.dup, final_newline: @final_newline
      }
    end

    def apply_edit(edit, direction)
      previous = direction == :before
      replace_edit_lines(edit, previous)
      restore_edit_metadata(edit, previous)
      clamp_cursor
    end

    def replace_edit_lines(edit, previous)
      from, to = previous ? [edit.after_lines, edit.before_lines] : [edit.before_lines, edit.after_lines]
      @lines[edit.row, from.length] = to.map(&:dup)
    end

    def restore_edit_metadata(edit, previous)
      @cursor_pos = (previous ? edit.before_cursor : edit.after_cursor).dup
      @line_ending = (previous ? edit.before_line_ending : edit.after_line_ending).dup
      @final_newline = previous ? edit.before_final_newline : edit.after_final_newline
    end

    def build_edit(row, before, after)
      Buffer::Edit.new(
        row:, before_lines: before.fetch(:lines), after_lines: after.fetch(:lines),
        before_cursor: before.fetch(:cursor), after_cursor: after.fetch(:cursor),
        before_line_ending: before.fetch(:line_ending), after_line_ending: after.fetch(:line_ending),
        before_final_newline: before.fetch(:final_newline), after_final_newline: after.fetch(:final_newline),
        position_change: position_change(row, before.fetch(:lines), after.fetch(:lines))
      )
    end
  end
end
