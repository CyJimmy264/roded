require "curses"
require_relative "curses/minibuffer"
require_relative "curses/input_decoder"
require_relative "curses/cursor_redraw"
require_relative "curses/cursor_snapshot_comparison"
require_relative "curses/text_geometry"
require_relative "curses/render_context"
require_relative "curses/input_operations"
require_relative "curses/viewport_operations"
require_relative "curses/layout_operations"
require_relative "curses/overlay_operations"
require_relative "curses/command_operations"
require_relative "curses/buffer_line_operations"
require_relative "curses/styled_segment_operations"
require_relative "curses/color_operations"
require_relative "curses/modeline_operations"

module Roded
  module Frontends
    # Coordinates curses input, screen drawing, and editor state updates.
    class Curses
      include Logging
      include CursesInputOperations
      include CursesViewportOperations
      include CursesLayoutOperations
      include CursesOverlayOperations
      include CursesCommandOperations
      include CursesBufferLineOperations
      include CursesStyledSegmentOperations
      include CursesColorOperations
      include CursesModelineOperations

      attr_accessor :keymap, :focus

      def initialize
        initialize_editor_state
        init_curses
        enable_bracketed_paste
        initialize_colors
        initialize_input_channel
        initialize_minibuffer
        draw_placeholder
      end

      def init_curses
        ::Curses.init_screen
        ::Curses.nonl
        ::Curses.raw
        ::Curses.noecho

        @screen = ::Curses.stdscr
        @screen.timeout = -1
        @screen.scrollok(true)
        @screen.keypad(true)
      end

      def close
        disable_bracketed_paste
        ::Curses.close_screen
        Signal.trap("WINCH", @previous_winch_handler) if @previous_winch_handler
        @wake_r&.close
        @wake_w&.close
      end

      def add_buffer(buffer)
        @buffers << buffer
        @current_buffer ||= buffer
        @data_lines = @current_buffer.lines
      end

      def remove_buffer(buffer)
        @buffers.delete(buffer)
      end

      private

      def initialize_editor_state
        @screen = nil
        @color_pairs = {}
        @buffers = []
        @current_buffer = nil
        @top = 0
        @input_decoder = CursesInputDecoder.new
      end

      def initialize_input_channel
        @stdin = $stdin
        @wake_r, @wake_w = IO.pipe
        @wake_w.sync = true
        install_resize_handler
      end

      def initialize_minibuffer
        @minibuffer_view = Curses::Minibuffer.new(@screen)
        @minibuffer_state = nil
      end

      def logger
        @logger ||= begin
          base_logger = Logging.logger
          tagged_logger = base_logger.dup
          tagged_logger.progname = "curses"
          tagged_logger
        end
      end
    end
  end
end
