require "curses"
require_relative "curses/minibuffer"
require_relative "curses/input_decoder"
require_relative "curses/cursor_redraw"
require_relative "curses/cursor_snapshot_comparison"
require_relative "curses/text_geometry"

module Roded
  module Frontends
    class Curses
      include Logging

      attr_accessor :keymap, :focus

      def initialize
        @screen = nil
        @color_pairs = {}
        @buffers = []
        @current_buffer = nil
        @top = 0
        @input_decoder = CursesInputDecoder.new
        init_curses
        enable_bracketed_paste
        initialize_colors
        @stdin = $stdin
        @wake_r, @wake_w = IO.pipe
        @wake_w.sync = true
        install_resize_handler
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
        disable_bracketed_paste
        ::Curses.close_screen
        Signal.trap("WINCH", @previous_winch_handler) if @previous_winch_handler
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
          @screen.addstr(CursesTextGeometry.clip(line, @screen.maxx))
        end
        @screen.setpos(0, 0)
        @screen.refresh
      end

      # Observer update method
      def update(buffer)
        return unless buffer == @current_buffer
        return if @layout_snapshot

        @data_lines = buffer.lines if buffer.respond_to?(:lines)
        ensure_cursor_visible
        redraw
      end

      # Scroll the display up by one line.
      def scroll_viewport_up
        return false unless @top.positive?

        @top -= 1
        redraw
        true
      end

      # Scroll the display down by one line.
      def scroll_viewport_down
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
        return handle_wake_event if key == :quit_signal
        return Event.new(:paste, { text: key.text }) if key.is_a?(CursesInputDecoder::PasteInput)

        Event.new(:key, { key: })
      end

      def render(buffer = nil)
        @current_buffer = buffer if buffer
        @data_lines = @current_buffer&.lines || []
        ensure_cursor_visible
        redraw
      end

      def page_size(window_id = nil)
        height = [@screen.maxy - 1, 1].max
        return [height - 1, 1].max unless @layout_snapshot && window_id

        rectangle = layout_rectangles(@layout_snapshot[:tree], 0, 0, @screen.maxx, height)
                    .find { |id, _x, _y, _width, _height| id == window_id }
        [rectangle ? rectangle.fetch(4) - 1 : height - 1, 1].max
      end

      # Add this method to handle Command objects
      def handle_command(command)
        logger.debug("handle_command: #{command.type}")
        # Core always follows cursor movement with an authoritative layout snapshot.
        # The old hint redraws the whole terminal, including the modeline row.
        return if command.type == :move_cursor

        case command.type
        when :render
          snapshot = command.payload[:editor_snapshot]
          snapshot ? render_layout(snapshot) : redraw
        when :minibuffer_render
          @minibuffer_state = command.payload
          render_minibuffer_overlay
        when :picker_render
          @picker_state = command.payload
          render_picker_overlay
        when :minibuffer_clear
          @minibuffer_state = nil
          @picker_state = nil
          @minibuffer_view.clear
        when :quit
          wake_getch
        end
      end

      def display_message(message)
        status_row = @screen.maxy - 1
        @screen.setpos(status_row, 0)
        @screen.clrtoeol
        @screen.addstr(CursesTextGeometry.clip(message, @screen.maxx))
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
        @input_decoder.read_key(@stdin, @wake_r)
      end

      def install_resize_handler
        @resize_pending = false
        @previous_winch_handler = Signal.trap("WINCH") do
          @resize_pending = true
          wake_getch
        end
      end

      def handle_wake_event
        drain_wake_pipe
        return resize_event if @resize_pending

        Event.new(:quit, {})
      end

      def resize_event
        @resize_pending = false
        ::Curses.resizeterm(0, 0)
        Event.new(:resize, {})
      end

      def enable_bracketed_paste
        $stdout.write("\e[?2004h")
        $stdout.flush
      end

      def disable_bracketed_paste
        $stdout.write("\e[?2004l")
        $stdout.flush
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
        visible_lines = (@data_lines || [])[@top, @screen.maxy] || []
        visible_lines.each_with_index do |line, idx|
          @screen.setpos(idx, 0)
          @screen.addstr(CursesTextGeometry.clip(line, @screen.maxx))
        end
        place_cursor
        render_minibuffer_overlay
        render_picker_overlay
        @screen.refresh
      end

      def render_layout(snapshot)
        return if CursesCursorRedraw.new(self).call(@layout_snapshot, snapshot)

        @layout_snapshot = snapshot
        @screen.clear
        area_height = [@screen.maxy - 1, 1].max
        rectangles = layout_rectangles(
          snapshot[:tree], 0, 0, @screen.maxx, area_height
        )
        records = snapshot[:windows].to_h { |item| [item[:id], item] }
        rectangles.each { |id, x, y, width, height| draw_window(records[id], x, y, width, height) }
        render_minibuffer_overlay
        render_picker_overlay
        @screen.refresh
      end

      def layout_rectangles(tree, x, y, width, height)
        return [[tree[:window_id], x, y, width, height]] if tree[:window_id]

        if tree[:direction] == :vertical
          first_width = (width * tree.fetch(:ratio, 0.5)).round.clamp(1, [width - 1, 1].max)
          layout_rectangles(tree[:first], x, y, first_width, height) +
            layout_rectangles(tree[:second], x + first_width, y,
                              width - first_width, height)
        else
          first_height = (height * tree.fetch(:ratio, 0.5)).round.clamp(1, [height - 1, 1].max)
          layout_rectangles(tree[:first], x, y, width, first_height) +
            layout_rectangles(tree[:second], x, y + first_height,
                              width, height - first_height)
        end
      end

      def draw_window(item, x, y, width, height)
        return unless item

        text_height = [height - 1, 0].max
        first_line = visible_origin(item[:point][:row], item[:top_line], text_height)
        left_column = CursesTextGeometry.horizontal_origin(
          item[:lines][item[:point][:row]].to_s, item[:point][:col], item[:left_column], width
        )
        item[:lines].slice(first_line, text_height).to_a.each_with_index do |line, index|
          draw_buffer_line(item, line, first_line + index, y + index, x, width, left_column)
        end
        modeline_row = y + height - 1
        draw_modeline(item, modeline_row, x, width)
        return unless item[:active] && height.positive? && width.positive?

        point = item[:point]
        cursor_line = item[:lines][point[:row]].to_s
        cursor_y = (y + point[:row] - first_line).clamp(y, [y + text_height - 1, y].max)
        cursor_x = (x + CursesTextGeometry.column(cursor_line, point[:col]) -
                    CursesTextGeometry.column(cursor_line, left_column)).clamp(x, x + width - 1)
        @screen.setpos(cursor_y, cursor_x)
      end

      def draw_modeline(item, row, x, width)
        writer = proc { write_at(row, x, modeline_text(item), width) }
        item[:active] ? @screen.attron(::Curses::A_REVERSE, &writer) : writer.call
      end

      def modeline_text(item)
        active_marker = item[:active] ? "*" : "-"
        modified = item[:modified] ? "*" : ""
        readonly = item[:readonly] ? " RO" : ""
        mode_name = item[:mode] || :plain
        point = item[:point]
        "#{active_marker} #{item[:name]}#{modified}#{readonly}  #{mode_name}  #{point[:row] + 1}:#{point[:col] + 1}"
      end

      def draw_buffer_line(item, line, buffer_row, screen_row, x, width, left_column)
        text = line[left_column..].to_s
        initial_column = CursesTextGeometry.column(line, left_column)
        tokens = item[:tokens]&.[](buffer_row).to_a
        selection = selection_columns(item, buffer_row, line.length)
        highlight = highlight_columns(item, buffer_row, line.length)
        boundaries = [0, text.length]
        tokens.each do |token|
          boundaries.push(token[:start] - left_column, token[:finish] - left_column)
        end
        boundaries.concat(selection.map { |column| column - left_column }) if selection
        boundaries.concat(highlight.map { |column| column - left_column }) if highlight
        boundaries = boundaries.map { |column| column.clamp(0, text.length) }.uniq.sort
        boundaries.each_cons(2) do |first, last|
          write_styled_segment(item, screen_row, x, text, first, last, width,
                               tokens, selection, highlight, left_column, initial_column)
        end
      end

      def write_styled_segment(_item, row, x, text, first, last, width, tokens, selection, highlight,
                               left_column, initial_column)
        return if first >= last

        token = tokens.find do |span|
          span[:start] <= first + left_column && span[:finish] >= last + left_column
        end
        selected = selection && first + left_column >= selection.first && last + left_column <= selection.last
        matched = highlight && first + left_column >= highlight.first && last + left_column <= highlight.last
        cell_offset = CursesTextGeometry.column(text, first, initial_column:)
        writer = proc do
          write_at(row, x + cell_offset, text[first...last], width - cell_offset,
                   initial_column: initial_column + cell_offset)
        end
        if selected
          @screen.attron(::Curses::A_REVERSE, &writer)
        elsif matched
          search_attribute = @search_pair ? ::Curses.color_pair(@search_pair) : ::Curses::A_STANDOUT
          @screen.attron(search_attribute, &writer)
        elsif token && (pair = @color_pairs[token[:category]])
          @screen.attron(::Curses.color_pair(pair), &writer)
        else
          writer.call
        end
      end

      def selection_columns(item, row, line_length)
        mark = item[:mark]
        point = item[:point]
        return unless mark && mark != point

        range_columns([mark, point], row, line_length)
      end

      def highlight_columns(item, row, line_length)
        range = item[:highlight]
        return unless range

        range_columns([range[:start], range[:finish]], row, line_length)
      end

      def range_columns(positions, row, line_length)
        first, last = positions.sort_by { |position| [position[:row], position[:col]] }
        return unless row.between?(first[:row], last[:row])

        start_column = row == first[:row] ? first[:col] : 0
        end_column = row == last[:row] ? last[:col] : line_length
        end_column = [end_column, line_length].min
        [start_column, end_column]
      end

      def visible_origin(point, origin, span)
        return point if point < origin
        return point - span + 1 if span.positive? && point >= origin + span

        origin
      end

      def write_at(row, column, text, width, initial_column: 0)
        return unless row.between?(0, @screen.maxy - 1) && column.between?(0, @screen.maxx - 1)
        return unless width.positive?

        @screen.setpos(row, column)
        @screen.addstr(CursesTextGeometry.clip(text, width, initial_column:))
      end

      def initialize_colors
        return unless ::Curses.has_colors?

        ::Curses.start_color
        background = begin
          ::Curses.use_default_colors
          -1
        rescue StandardError
          ::Curses::COLOR_BLACK
        end
        colors = {
          comment: ::Curses::COLOR_WHITE,
          string: ::Curses::COLOR_GREEN,
          keyword: ::Curses::COLOR_MAGENTA,
          number: ::Curses::COLOR_YELLOW,
          symbol: ::Curses::COLOR_CYAN,
          heading: ::Curses::COLOR_BLUE,
          punctuation: ::Curses::COLOR_WHITE
        }
        colors.each_with_index do |(category, foreground), index|
          pair = index + 1
          ::Curses.init_pair(pair, foreground, background)
          @color_pairs[category] = pair
        end
        @search_pair = colors.length + 1
        ::Curses.init_pair(@search_pair, ::Curses::COLOR_BLACK, ::Curses::COLOR_YELLOW)
      rescue StandardError
        @color_pairs = {}
        @search_pair = nil
      end

      def place_cursor
        return unless @current_buffer

        cursor_row = @current_buffer.cursor_row - @top
        cursor_line = @current_buffer.lines[@current_buffer.cursor_row].to_s
        cursor_col = CursesTextGeometry.column(cursor_line, @current_buffer.cursor_col)
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

      def render_picker_overlay
        return unless @picker_state

        render_picker_rows(PickerViewport.slice(
                             @picker_state[:candidates], @picker_state[:selected_index],
                             limit: [@screen.maxy - 2, 0].max
                           ))
      end

      def render_picker_rows(rows)
        start_row = [@screen.maxy - rows[:candidates].length - 2, 0].max
        rows[:candidates].each_with_index do |candidate, index|
          marker = index == rows[:selected_index] ? "> " : "  "
          write_at(start_row + index, 0, "#{marker}#{candidate}", @screen.maxx)
        end
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
