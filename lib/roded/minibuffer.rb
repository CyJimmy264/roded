module Roded
  # Mini-buffer state independent of any frontend.
  class Minibuffer
    attr_reader :prompt, :cursor

    def initialize
      @prompt = ""
      @buffer = []
      @cursor = 0
      @active = false
    end

    def start(prompt)
      @prompt = prompt
      @buffer = []
      @cursor = 0
      @active = true
    end

    def cancel
      @active = false
      nil
    end

    def submit
      text = @buffer.join
      @active = false
      text
    end

    def active?
      @active
    end

    def text
      @buffer.join
    end

    def replace_text(value)
      @buffer = value.to_s.each_char.to_a
      @cursor = @buffer.length
    end

    def move_left
      @cursor = [@cursor - 1, 0].max
    end

    def move_right
      @cursor = [@cursor + 1, @buffer.length].min
    end

    def move_to_start
      @cursor = 0
    end

    def move_to_end
      @cursor = @buffer.length
    end

    def backspace
      return unless @cursor.positive?

      @buffer.delete_at(@cursor - 1)
      @cursor -= 1
    end

    def delete_char
      return unless @cursor < @buffer.length

      @buffer.delete_at(@cursor)
    end

    def insert_char(char)
      return if char.nil? || char.empty?

      @buffer.insert(@cursor, char)
      @cursor += 1
    end
  end
end
