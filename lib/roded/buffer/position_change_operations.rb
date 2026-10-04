require_relative "text_change_offsets"

module Roded
  # Computes precise point/mark transformations for edits and history replay.
  module BufferPositionChangeOperations
    private

    def normalize_buffer_position(position)
      row = position.fetch(:row, 0).to_i.clamp(0, @lines.length - 1)
      col = position.fetch(:col, 0).to_i.clamp(0, @lines[row].length)
      { row:, col: }
    end

    def position_change(row, before_lines, after_lines)
      return if before_lines == after_lines

      first, suffix = unchanged_lines(before_lines, after_lines)
      before = changed_text(before_lines, first, suffix)
      after = changed_text(after_lines, first, suffix)
      return if before == after

      build_position_change(row + first, before, after)
    end

    def changed_text(lines, first, suffix)
      lines[first, lines.length - first - suffix].join("\n")
    end

    def build_position_change(row, before, after)
      prefix, before_end, after_end = BufferTextChangeOffsets.new(before, after).offsets
      Buffer::PositionChange.new(
        start: position_at_offset(row, before, prefix),
        old_end: position_at_offset(row, before, before_end),
        new_end: position_at_offset(row, after, after_end)
      )
    end

    def unchanged_lines(before, after)
      # Keep an anchor row so joining/splitting lines retains the boundary newline.
      limit = [before.length, after.length].min - 1
      first = 0
      first += 1 while first < limit && before[first] == after[first]
      suffix = 0
      suffix += 1 while suffix < limit - first && before[-suffix - 1] == after[-suffix - 1]
      [first, suffix]
    end

    def position_at_offset(base_row, text, offset)
      preceding = text.byteslice(0, offset)
      last_newline = preceding.rindex("\n")
      column = last_newline ? preceding.length - last_newline - 1 : preceding.length
      { row: base_row + preceding.b.count("\n"), col: column }.freeze
    end
  end
end
