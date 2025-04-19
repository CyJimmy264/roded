module Roded
  class Buffer
    attr_accessor :lines, :filename, :cursor_pos

    def initialize(filename = nil)
      @filename = filename
      @lines = [""] # Начинаем с пустой строки
      @cursor_pos = { row: 0, col: 0 } # Позиция курсора: строка и столбец
      @observers = []
    end

    def add_observer(observer)
      @observers << observer unless @observers.include?(observer)
    end

    def remove_observer(observer)
      @observers.delete(observer)
    end

    def notify_observers
      @observers.each { |obs| obs.update(self) }
    end

    def insert_char(char)
      current_line = @lines[@cursor_pos[:row]]
      @lines[@cursor_pos[:row]] = current_line.insert(@cursor_pos[:col], char)
      move_cursor_right
      notify_observers
    end

    def backspace
      if @cursor_pos[:col].positive?
        current_line = @lines[@cursor_pos[:row]]
        @lines[@cursor_pos[:row]] =
          current_line.slice!(0...@cursor_pos[:col] - 1) + current_line.slice!(@cursor_pos[:col]..-1)
        move_cursor_left
        notify_observers
      elsif @cursor_pos[:row].positive? # Backspace на начале строки, перенос на предыдущую
        # TODO: Реализовать перенос строки
      end
    end

    def move_cursor_left
      @cursor_pos[:col] = [@cursor_pos[:col] - 1, 0].max
      notify_observers
    end

    def move_cursor_right
      @cursor_pos[:col] += 1 # TODO: Ограничить длиной строки
      notify_observers
    end

    def move_cursor_up
      @cursor_pos[:row] = [@cursor_pos[:row] - 1, 0].max
      notify_observers
      # TODO: Корректировка позиции столбца при переходе на более короткую строку
    end

    def move_cursor_down
      @cursor_pos[:row] += 1 # TODO: Ограничить количеством строк
      notify_observers
      # TODO: Корректировка позиции столбца при переходе на более короткую строку
    end

    def to_s
      @lines.join("\n") # Возвращает текст буфера как строку
    end

    def line_at_cursor
      @lines[@cursor_pos[:row]]
    end

    def cursor_row
      @cursor_pos[:row]
    end

    def cursor_col
      @cursor_pos[:col]
    end
  end
end
