module Roded
  class Window
    attr_accessor :buffer

    def initialize(buffer)
      @buffer = buffer
    end

    def display
      system "clear" # Clear the console screen (works in most terminals)
      puts @buffer
    end
  end
end
