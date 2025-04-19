require "curses"
require_relative "../event"

module Roded
  module Frontends
    class Curses
      def initialize(buffer = nil)
        @data_lines = ["Welcome to the Roded!", "Press 'q' to quit"]
        @screen = nil
        @top = nil
        @current_x = 0
        @current_y = 0
        @buffer = buffer
        if @buffer
          @buffer.add_observer(self)
          update(@buffer)
        end
        init_curses
        load_file
      end

      def init_curses
        Curses.init_screen
        Curses.nonl
        Curses.cbreak
        Curses.noecho

        @screen = Curses.stdscr

        @screen.scrollok(true)
        @screen.keypad(true)
      end

      def load_file
        @top = 0
        @data_lines[0..@screen.maxy - 1].each_with_index do |line, idx|
          @screen.setpos(idx, 0)
          @screen.addstr(line)
        end
        @screen.setpos(0, 0)
        @screen.refresh
      rescue
        raise "cannot open file '#{filename}' for reading"
      end

      # Observer update method
      def update(buffer)
        # Update @data_lines from buffer
        @data_lines = buffer.lines if buffer.respond_to?(:lines)
        # Redraw screen if initialized
        if @screen
          @screen.clear
          load_file
        end
      end

      # Scroll the display up by one line.
      def scroll_up
        if @top > 0
          @screen.scrl(-1)
          @top -= 1
          str = @data_lines[@top]
          if str
            @screen.setpos(@current_y, @current_x)
            @screen.addstr(str)
          end
          true
        else
          false
        end
      end

      # Scroll the display down by one line.
      def scroll_down
        if @top + @screen.maxy < @data_lines.length
          @screen.scrl(1)
          @top += 1
          str = @data_lines[@top + @screen.maxy - 1]
          if str
            @screen.setpos(@screen.maxy - 1, 0)
            @screen.addstr(str)
          end
          true
        else
          false
        end
      end

      def get_event
        case Curses.getch
        when Curses::KEY_DOWN, 'j'
          Event.new(:move_down, {})
        when Curses::KEY_UP, 'k'
          Event.new(:move_up, {})
        when Curses::KEY_LEFT, 'h'
          Event.new(:move_left, {})
        when Curses::KEY_RIGHT, 'l'
          Event.new(:move_right, {})
        when 'q', ?\C-c
          Event.new(:quit, {})
        else
          Event.new(:noop, {})
        end
      end

      def render(buffer = nil)
        @data_lines = buffer.lines if buffer && buffer.respond_to?(:lines)
        @screen.clear
        load_file
      end
    end
  end
end
