module Roded
  # Finds a character-aligned replacement span without allocating every UTF-8 character.
  class BufferTextChangeOffsets
    def initialize(before, after)
      @before = before
      @after = after
    end

    def offsets
      return character_offsets unless byte_comparable?

      first = common_prefix
      first -= 1 while continuation_byte?(@before, first)
      suffix = common_suffix(first)
      suffix -= 1 while continuation_byte?(@before, @before.bytesize - suffix)
      [first, @before.bytesize - suffix, @after.bytesize - suffix]
    end

    private

    def byte_comparable?
      [@before, @after].all? do |text|
        text.ascii_only? || (text.encoding == Encoding::UTF_8 && text.valid_encoding?)
      end
    end

    def continuation_byte?(text, offset)
      text.getbyte(offset)&.between?(0x80, 0xbf)
    end

    def common_prefix
      limit = [@before.bytesize, @after.bytesize].min
      first = 0
      first += 1 while first < limit && @before.getbyte(first) == @after.getbyte(first)
      first
    end

    def common_suffix(first)
      limit = [@before.bytesize, @after.bytesize].min - first
      suffix = 0
      suffix += 1 while suffix < limit && @before.getbyte(-suffix - 1) == @after.getbyte(-suffix - 1)
      suffix
    end

    def character_offsets
      before = @before.each_char.to_a
      after = @after.each_char.to_a
      first = character_prefix(before, after)
      suffix = character_suffix(before, after, first)
      character_byte_offsets(before, after, first, suffix)
    end

    def character_prefix(before, after)
      first = 0
      first += 1 while first < [before.length, after.length].min && before[first] == after[first]
      first
    end

    def character_byte_offsets(before, after, first, suffix)
      [before.take(first).join.bytesize, before.take(before.length - suffix).join.bytesize,
       after.take(after.length - suffix).join.bytesize]
    end

    def character_suffix(before, after, first)
      limit = [before.length, after.length].min - first
      suffix = 0
      suffix += 1 while suffix < limit && before[-suffix - 1] == after[-suffix - 1]
      suffix
    end
  end
end
