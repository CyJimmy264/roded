module Roded
  # Roded::Buffer - Buffer class for the Roded text editor
  #
  # A Buffer is a container for text. It is the primary data structure
  # used by the Roded text editor. It provides ways to manipulate the
  # text, such as inserting and deleting characters, and allows other
  # objects to observe its state.
  class Buffer
    attr_accessor :lines, :filename, :cursor_pos, :readonly

    def initialize(name = nil)
      @name = name
      @filename = nil
      @lines = [String.new("")]
      @cursor_pos = { row: 0, col: 0 }
      @observers = []
      @readonly = false
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
      return if readonly
      return if char.nil? || char.empty?

      line = @lines[@cursor_pos[:row]]
      @lines[@cursor_pos[:row]] = line.dup.insert(@cursor_pos[:col], char)
      @cursor_pos[:col] = [@cursor_pos[:col] + 1, line_at_cursor.length].min
      notify_observers
    end

    def backspace
      return if readonly

      if @cursor_pos[:col].positive?
        line = @lines[@cursor_pos[:row]]
        line.slice!(@cursor_pos[:col] - 1)
        @lines[@cursor_pos[:row]] = line
        @cursor_pos[:col] = [@cursor_pos[:col] - 1, 0].max
        notify_observers
      elsif @cursor_pos[:row].positive? # Backspace at start of line should join previous
        prev_line = @lines[@cursor_pos[:row] - 1]
        current_line = @lines[@cursor_pos[:row]]
        new_col = prev_line.length
        @lines[@cursor_pos[:row] - 1] = prev_line + current_line
        @lines.delete_at(@cursor_pos[:row])
        @cursor_pos[:row] -= 1
        @cursor_pos[:col] = new_col
        notify_observers
      end
    end

    def delete_char
      return if readonly

      line = @lines[@cursor_pos[:row]]
      if @cursor_pos[:col] < line.length
        line.slice!(@cursor_pos[:col])
        @lines[@cursor_pos[:row]] = line
        notify_observers
      elsif @cursor_pos[:row] < @lines.length - 1
        next_line = @lines[@cursor_pos[:row] + 1]
        @lines[@cursor_pos[:row]] = line + next_line
        @lines.delete_at(@cursor_pos[:row] + 1)
        notify_observers
      end
    end

    def kill_line(kill_ring)
      return if readonly

      line = @lines[@cursor_pos[:row]]
      if @cursor_pos[:col] < line.length
        killed = line[@cursor_pos[:col]..]
        kill_ring.push(killed)
        @lines[@cursor_pos[:row]] = line[0...@cursor_pos[:col]]
        notify_observers
      elsif @cursor_pos[:row] < @lines.length - 1
        next_line = @lines[@cursor_pos[:row] + 1]
        @lines[@cursor_pos[:row]] = line + next_line
        @lines.delete_at(@cursor_pos[:row] + 1)
        notify_observers
      end
    end

    def move_cursor_left
      @cursor_pos[:col] = [@cursor_pos[:col] - 1, 0].max
      notify_observers
    end

    def move_cursor_right
      @cursor_pos[:col] = [@cursor_pos[:col] + 1, line_at_cursor.length].min
      notify_observers
    end

    def move_cursor_line_start
      @cursor_pos[:col] = 0
      notify_observers
    end

    def move_cursor_line_end
      line = line_at_cursor || ""
      @cursor_pos[:col] = line.length
      notify_observers
    end

    def move_cursor_up
      @cursor_pos[:row] = [@cursor_pos[:row] - 1, 0].max
      clamp_cursor_col
      notify_observers
    end

    def move_cursor_down
      @cursor_pos[:row] = [@cursor_pos[:row] + 1, @lines.length - 1].min
      clamp_cursor_col
      notify_observers
    end

    def to_s
      @lines.join("\n")
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

    def newline
      return if readonly

      line = @lines[@cursor_pos[:row]]
      before = line[0...@cursor_pos[:col]]
      after = line[@cursor_pos[:col]..] || ""
      @lines[@cursor_pos[:row]] = before
      @lines.insert(@cursor_pos[:row] + 1, after)
      @cursor_pos[:row] += 1
      @cursor_pos[:col] = 0
      notify_observers
    end

    private

    def clamp_cursor_col
      @cursor_pos[:col] = [@cursor_pos[:col], line_at_cursor.length].min
    end
  end
end
