require_relative "text_geometry"

module Roded
  module Frontends
    class Curses
      class Minibuffer
        def initialize(screen)
          @screen = screen
        end

        def render(prompt:, text:, cursor:)
          row = @screen.maxy - 1
          line = "#{prompt}#{text}"
          @screen.setpos(row, 0)
          @screen.clrtoeol
          @screen.addstr(CursesTextGeometry.clip(line, @screen.maxx))
          cursor_x = CursesTextGeometry.width("#{prompt}#{text.to_s[0, cursor]}")
          cursor_x = cursor_x.clamp(0, @screen.maxx - 1)
          @screen.setpos(row, cursor_x)
          @screen.refresh
        end

        def clear
          row = @screen.maxy - 1
          @screen.setpos(row, 0)
          @screen.clrtoeol
          @screen.refresh
        end
      end
    end
  end
end
