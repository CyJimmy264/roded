module Roded
  module Frontends
    # Groups terminal coordinates and buffer state for curses drawing operations.
    module CursesRenderContext
      Rectangle = Struct.new(:window_id, :left, :top, :width, :height, keyword_init: true)
      BufferLine = Struct.new(:item, :line, :buffer_row, :screen_row, :left, :width, :left_column, keyword_init: true)
      StyledSegment = Struct.new(
        :row, :left, :text, :first_offset, :last, :width, :tokens, :selection, :highlight,
        :left_column, :initial_column, keyword_init: true
      )
    end
  end
end
