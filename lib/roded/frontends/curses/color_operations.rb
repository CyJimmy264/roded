module Roded
  module Frontends
    # Initializes terminal color pairs with a monochrome fallback.
    module CursesColorOperations
      COLOR_CATEGORIES = {
        comment: ::Curses::COLOR_WHITE,
        string: ::Curses::COLOR_GREEN,
        keyword: ::Curses::COLOR_MAGENTA,
        number: ::Curses::COLOR_YELLOW,
        symbol: ::Curses::COLOR_CYAN,
        heading: ::Curses::COLOR_BLUE,
        punctuation: ::Curses::COLOR_WHITE
      }.freeze

      private

      def initialize_colors
        return unless ::Curses.has_colors?

        ::Curses.start_color
        initialize_color_pairs(default_background)
      rescue StandardError
        @color_pairs = {}
        @search_pair = nil
      end

      def default_background
        ::Curses.use_default_colors
        -1
      rescue StandardError
        ::Curses::COLOR_BLACK
      end

      def initialize_color_pairs(background)
        COLOR_CATEGORIES.each_with_index do |(category, foreground), index|
          pair = index + 1
          ::Curses.init_pair(pair, foreground, background)
          @color_pairs[category] = pair
        end
        @search_pair = COLOR_CATEGORIES.length + 1
        ::Curses.init_pair(@search_pair, ::Curses::COLOR_BLACK, ::Curses::COLOR_YELLOW)
      end
    end
  end
end
