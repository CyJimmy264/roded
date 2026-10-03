module Roded
  # Roded::Buffer - Buffer class for the Roded text editor
  #
  # A Buffer is a container for text. It is the primary data structure
  # used by the Roded text editor. It provides ways to manipulate the
  # text, such as inserting and deleting characters, and allows other
  # objects to observe its state.
  class Buffer
    attr_accessor :filename, :readonly, :file_revision
    attr_reader :lines, :cursor_pos, :line_ending, :final_newline, :name

    def initialize(name = nil)
      @name = name
      @filename = nil
      @file_revision = nil
      @lines = [String.new("")]
      @cursor_pos = { row: 0, col: 0 }
      @line_ending = "\n"
      @final_newline = false
      @observers = []
      @readonly = false
      @saved_text = to_s
    end

    def lines=(lines)
      @lines = Array(lines).map(&:to_s)
      @lines = [""] if @lines.empty?
      clamp_cursor
    end

    def load_text(text)
      validate_text!(text)
      @line_ending = text.scan(/\r\n|\n/).uniq.first || "\n"
      @final_newline = text.end_with?("\n")
      self.lines = text.gsub("\r\n", "\n").split("\n", -1).tap { |lines| lines.pop if @final_newline }
      @cursor_pos = { row: 0, col: 0 }
      mark_saved
      self
    end

    def cursor_pos=(position)
      @cursor_pos = { row: position.fetch(:row, 0).to_i, col: position.fetch(:col, 0).to_i }
      clamp_cursor
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

    def move_cursor_page_up(page_size)
      move_cursor_by_page(-page_size.to_i)
    end

    def move_cursor_page_down(page_size)
      move_cursor_by_page(page_size.to_i)
    end

    def to_s
      text = @lines.join(@line_ending)
      @final_newline ? text + @line_ending : text
    end

    def modified?
      to_s != @saved_text
    end

    def mark_saved
      @saved_text = to_s
    end

    def final_newline=(value)
      @final_newline = !!value
    end

    def line_ending=(value)
      raise ArgumentError, "unsupported line ending" unless ["\n", "\r\n"].include?(value)

      @line_ending = value
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

    def move_cursor_by_page(delta)
      @cursor_pos[:row] = [@cursor_pos[:row] + delta, 0].max
      @cursor_pos[:row] = [@cursor_pos[:row], @lines.length - 1].min
      clamp_cursor_col
      notify_observers
    end

    def clamp_cursor_col
      @cursor_pos[:col] = [@cursor_pos[:col], line_at_cursor.length].min
    end

    def clamp_cursor
      @cursor_pos[:row] = @cursor_pos[:row].to_i.clamp(0, @lines.length - 1)
      clamp_cursor_col
    end

    def validate_text!(text)
      raise ArgumentError, "text must be valid UTF-8" unless text.encoding == Encoding::UTF_8 && text.valid_encoding?
      raise ArgumentError, "mixed line endings are not supported" if text.scan(/\r\n|\n/).uniq.length > 1
    end
  end
end
