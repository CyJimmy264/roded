module Roded
  class StatusBar
    attr_accessor :buffer

    def initialize(buffer)
      @buffer = buffer
    end

    def display
      filename = @buffer.filename || "безымянный"
      row = @buffer.cursor_row + 1 # Нумерация строк с 1
      col = @buffer.cursor_col + 1 # Нумерация столбцов с 1
      puts "-- Ruby Emacs -- #{filename} (строка: #{row}, столбец: #{col})"
    end
  end
end
