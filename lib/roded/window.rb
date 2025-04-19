module Roded
  class Window
    attr_accessor :buffer

    def initialize(buffer)
      @buffer = buffer
    end

    def display
      system "clear" # Очистка экрана консоли (работает в большинстве терминалов)
      puts @buffer
    end
  end
end
