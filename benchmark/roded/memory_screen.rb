module Roded
  module Benchmarking
    # Exercises curses text geometry and rendering without a terminal or ncurses I/O.
    class MemoryScreen
      attr_reader :maxx, :maxy, :writes, :refreshes

      def initialize
        @maxx = 120
        @maxy = 40
        @writes = 0
        @refreshes = 0
      end

      def clear; end

      def clrtoeol; end

      def setpos(_row, _column); end

      def addstr(text)
        @writes += text.bytesize
      end

      def refresh
        @refreshes += 1
      end

      def attron(_attribute)
        yield self
      end
    end
  end
end
