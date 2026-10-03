module Roded
  # Computes precise point/mark transformations for edits and history replay.
  module BufferPositionChangeOperations
    private

    def position_change(row, before_lines, after_lines)
      before_chars = before_lines.join("\n").each_char.to_a
      after_chars = after_lines.join("\n").each_char.to_a
      prefix, before_end, after_end = changed_offsets(before_chars, after_chars)
      return if before_end.nil?

      Buffer::PositionChange.new(
        start: position_at_offset(row, before_chars, prefix),
        old_end: position_at_offset(row, before_chars, before_end),
        new_end: position_at_offset(row, after_chars, after_end)
      )
    end

    def changed_offsets(before_chars, after_chars)
      prefix = common_prefix_length(before_chars, after_chars)
      suffix = common_suffix_length(before_chars, after_chars, prefix)
      return [nil, nil, nil] if prefix == before_chars.length && prefix == after_chars.length

      [prefix, before_chars.length - suffix, after_chars.length - suffix]
    end

    def common_prefix_length(before_chars, after_chars)
      index = 0
      index += 1 while index < before_chars.length && index < after_chars.length &&
                       before_chars[index] == after_chars[index]
      index
    end

    def common_suffix_length(before_chars, after_chars, prefix)
      suffix = 0
      while suffix < before_chars.length - prefix && suffix < after_chars.length - prefix &&
            before_chars[-suffix - 1] == after_chars[-suffix - 1]
        suffix += 1
      end
      suffix
    end

    def position_at_offset(base_row, chars, offset)
      preceding = chars.take(offset).join
      parts = preceding.split("\n", -1)
      parts = [""] if parts.empty?
      { row: base_row + parts.length - 1, col: parts.last.length }.freeze
    end
  end
end
