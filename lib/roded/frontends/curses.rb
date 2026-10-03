require "curses"
require_relative "curses/minibuffer"

module Roded
  module Frontends
    class Curses
      include Logging
      attr_accessor :keymap, :focus

      def initialize
        @screen = nil
        @buffers = []
        @current_buffer = nil
        @top = 0
        @input_buffer = +"".b
        init_curses
        @stdin = STDIN
        @wake_r, @wake_w = IO.pipe
        @wake_w.sync = true
        @minibuffer_view = Curses::Minibuffer.new(@screen)
        @minibuffer_state = nil
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
        ::Curses.close_screen
        @wake_r&.close
        @wake_w&.close
      end

      def add_buffer(buffer)
        @buffers << buffer
        @current_buffer ||= buffer
        buffer.add_observer(self)
        update(buffer)
      end

      def remove_buffer(buffer)
        @buffers.delete(buffer)
        buffer.remove_observer(self)
      end

      def draw_placeholder
        lines = ["Welcome Curses", "M-x for commands, C-x C-c to quit"]
        @screen.clear
        lines.first(@screen.maxy).each_with_index do |line, idx|
          @screen.setpos(idx, 0)
          @screen.addstr(line[0, @screen.maxx])
        end
        @screen.setpos(0, 0)
        @screen.refresh
      end

      # Observer update method
      def update(buffer)
        return unless buffer == @current_buffer

        return if @layout_snapshot && @layout_snapshot[:windows].length > 1

        @data_lines = buffer.lines if buffer.respond_to?(:lines)
        ensure_cursor_visible
        redraw
      end

      # Scroll the display up by one line.
      def scroll_up
        return false unless @top.positive?

        @top -= 1
        redraw
        true
      end

      # Scroll the display down by one line.
      def scroll_down
        return false unless @current_buffer
        return false if @top + @screen.maxy >= @current_buffer.lines.length

        @top += 1
        redraw
        true
      end

      def next_event
        logger.debug("next_event: read_key")
        key = read_key
        logger.debug("next_event: read_key: #{key.inspect}")
        return Event.new(:noop, {}) unless key
        return Event.new(:quit, {}) if key == :quit_signal
        Event.new(:key, { key: })
      end

      def render(buffer = nil)
        @current_buffer = buffer if buffer
        @data_lines = @current_buffer&.lines || []
        ensure_cursor_visible
        redraw
      end

      def page_size
        [@screen.maxy - 1, 1].max
      end

      # Add this method to handle Command objects
      def handle_command(command)
        logger.debug("handle_command: #{command.type}")
        case command.type
        when :move_cursor
          return if @layout_snapshot && @layout_snapshot[:windows].length > 1

          direction = command.payload[:direction]
          if %i[up down].include?(direction)
            send("scroll_#{direction}")
          else
            ensure_cursor_visible(direction)
            redraw
          end
        when :render
          snapshot = command.payload[:editor_snapshot]
          snapshot ? render_layout(snapshot) : redraw
        when :minibuffer_render
          @minibuffer_state = command.payload
          render_minibuffer_overlay
        when :minibuffer_clear
          @minibuffer_state = nil
          @minibuffer_view.clear
        when :quit
          wake_getch
        end
      end

      def display_message(message)
        status_row = @screen.maxy - 1
        @screen.setpos(status_row, 0)
        @screen.clrtoeol
        @screen.addstr(message.to_s[0, @screen.maxx])
        @screen.refresh
      end

      private

      def logger
        @logger ||= begin
          base_logger = Logging.logger
          tagged_logger = base_logger.dup
          tagged_logger.progname = "curses"
          tagged_logger
        end
      end

      def read_key
        readable, = IO.select([@stdin, @wake_r])
        return nil unless readable

        if readable.include?(@wake_r)
          drain_wake_pipe
          return :quit_signal
        end

        read_input_key
      rescue IO::WaitReadable
        decode_input_buffer
      end

      def read_escape_sequence
        sequence = +""
        loop do
          sequence << @stdin.read_nonblock(1)
        rescue IO::WaitReadable
          break
        end

        logger.debug("read_escape_sequence: #{sequence.inspect}")

        return "Esc" if sequence.empty?

        if sequence.start_with?("[")
          return "Up" if sequence == "[A"
          return "Down" if sequence == "[B"
          return "Right" if sequence == "[C"
          return "Left" if sequence == "[D"
          return "Delete" if sequence == "[3~"
        end

        if sequence.start_with?("O")
          return "Up" if sequence == "OA"
          return "Down" if sequence == "OB"
          return "Right" if sequence == "OC"
          return "Left" if sequence == "OD"
        end

        utf8 = sequence.dup.force_encoding("UTF-8")
        return "M-#{utf8}" if utf8.valid_encoding?

        return "M-#{normalize_input(sequence)}" if sequence.length == 1

        "Esc"
      end

      def read_input_key
        loop do
          ch = @stdin.read_nonblock(1)
          return nil unless ch

          if ch == "\e"
            @input_buffer.clear
            return read_escape_sequence
          end

          @input_buffer << ch
          key = decode_input_buffer
          return key if key
        end
      rescue IO::WaitReadable
        decode_input_buffer
      end

      def decode_input_buffer
        return nil if @input_buffer.empty?

        utf8 = @input_buffer.dup.force_encoding("UTF-8")
        if utf8.valid_encoding?
          @input_buffer.clear
          return normalize_input(utf8)
        end

        expected = expected_utf8_length(@input_buffer.getbyte(0))
        if expected.nil? || @input_buffer.bytesize >= expected
          @input_buffer.clear
        end

        nil
      end

      def expected_utf8_length(byte)
        return 1 if byte < 0x80
        return 2 if byte.between?(0xC0, 0xDF)
        return 3 if byte.between?(0xE0, 0xEF)
        return 4 if byte.between?(0xF0, 0xF7)

        nil
      end

      def normalize_input(ch)
        return "Enter" if ch == "\n" || ch == "\r"
        return "Backspace" if ch == "\u007F" || ch == "\b"

        codepoint = ch.ord
        return "C-#{(codepoint + 96).chr}" if codepoint.between?(1, 26)

        ch
      end

      def ensure_cursor_visible(_direction = nil)
        return unless @current_buffer

        row = @current_buffer.cursor_row
        if row < @top
          @top = row
        elsif row >= @top + @screen.maxy
          @top = row - @screen.maxy + 1
        end
      end

      def redraw
        return unless @screen

        @screen.clear
        visible_lines = (@data_lines || [])[ @top, @screen.maxy ] || []
        visible_lines.each_with_index do |line, idx|
          @screen.setpos(idx, 0)
          @screen.addstr(line.ljust(@screen.maxx)[0, @screen.maxx])
        end
        place_cursor
        render_minibuffer_overlay
        @screen.refresh
      end

      def render_layout(snapshot)
        @layout_snapshot = snapshot
        @screen.clear
        area_height = [@screen.maxy - 1, 1].max
        rectangles = layout_rectangles(
          snapshot[:tree], 0, 0, @screen.maxx, area_height
        )
        records = snapshot[:windows].to_h { |item| [item[:id], item] }
        rectangles.each { |id, x, y, width, height| draw_window(records[id], x, y, width, height) }
        render_minibuffer_overlay
        @screen.refresh
      end

      def layout_rectangles(tree, x, y, width, height)
        return [[tree[:window_id], x, y, width, height]] if tree[:window_id]

        if tree[:direction] == :vertical
          first_width = width / 2
          layout_rectangles(tree[:first], x, y, first_width, height) +
            layout_rectangles(tree[:second], x + first_width, y,
                              width - first_width, height)
        else
          first_height = height / 2
          layout_rectangles(tree[:first], x, y, width, first_height) +
            layout_rectangles(tree[:second], x, y + first_height,
                              width, height - first_height)
        end
      end

      def draw_window(item, x, y, width, height)
        return unless item

        text_height = [height - 1, 0].max
        first_line = visible_origin(item[:point][:row], item[:top_line], text_height)
        left_column = horizontal_origin(item[:point][:col], item[:left_column], width)
        item[:lines].slice(first_line, text_height).to_a.each_with_index do |line, index|
          write_at(y + index, x, line[left_column..].to_s, width)
        end
        modeline_row = y + height - 1
        point = item[:point]
        active_marker = item[:active] ? "*" : "-"
        mode = "#{active_marker} #{item[:name]}  #{point[:row] + 1}:#{point[:col] + 1}"
        write_at(modeline_row, x, mode, width)
        return unless item[:active] && height.positive? && width.positive?

        cursor_y = y + point[:row] - first_line
        cursor_x = x + point[:col] - left_column
        cursor_y = cursor_y.clamp(y, [y + text_height - 1, y].max)
        cursor_x = cursor_x.clamp(x, x + width - 1)
        @screen.setpos(cursor_y, cursor_x)
      end

      def visible_origin(point, origin, span)
        return point if point < origin
        return point - span + 1 if span.positive? && point >= origin + span

        origin
      end

      def horizontal_origin(point, origin, span)
        return point if point < origin
        return point - span + 1 if span.positive? && point >= origin + span

        origin
      end

      def write_at(row, column, text, width)
        return unless row.between?(0, @screen.maxy - 1) && column.between?(0, @screen.maxx - 1)
        return unless width.positive?

        @screen.setpos(row, column)
        @screen.addstr(text.to_s[0, width])
      end

      def place_cursor
        return unless @current_buffer

        cursor_row = @current_buffer.cursor_row - @top
        cursor_col = @current_buffer.cursor_col
        cursor_row = cursor_row.clamp(0, @screen.maxy - 1)
        cursor_col = cursor_col.clamp(0, @screen.maxx - 1)
        @screen.setpos(cursor_row, cursor_col)
      end

      def render_minibuffer_overlay
        return unless @minibuffer_state

        @minibuffer_view.render(
          prompt: @minibuffer_state[:prompt],
          text: @minibuffer_state[:text],
          cursor: @minibuffer_state[:cursor]
        )
      end

      def wake_getch
        @wake_w.write_nonblock(".")
      rescue IO::WaitWritable, Errno::EPIPE
        nil
      end

      def drain_wake_pipe
        loop do
          @wake_r.read_nonblock(64)
        end
      rescue IO::WaitReadable
        nil
      end
    end
  end
end
