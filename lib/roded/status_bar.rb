module Roded
  # Displays buffer metadata for the legacy console interface.
  class StatusBar
    attr_accessor :buffer

    def initialize(buffer)
      @buffer = buffer
    end

    def display
      filename = @buffer.filename || "untitled"
      row = @buffer.cursor_row + 1 # Row numbers start at 1
      col = @buffer.cursor_col + 1 # Column numbers start at 1
      puts "-- Ruby Emacs -- #{filename} (row: #{row}, col: #{col})"
    end
  end
end
