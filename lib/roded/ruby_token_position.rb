module Roded
  # Native lexer tokens arrive in source order; walk line offsets once, in bytes.
  class RubyTokenPosition
    def initialize(offsets)
      @offsets = offsets
      @row = 0
    end

    def position(location)
      offset = location.start_offset
      @row += 1 while @offsets[@row + 1] && @offsets[@row + 1] <= offset
      [@row + 1, offset - @offsets[@row]]
    end
  end
end
