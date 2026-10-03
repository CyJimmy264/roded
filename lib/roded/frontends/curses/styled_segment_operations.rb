module Roded
  module Frontends
    # Applies terminal attributes to a text segment and clips screen writes.
    module CursesStyledSegmentOperations
      private

      def write_styled_segment(segment)
        return if segment.first_offset >= segment.last

        style = segment_style(segment)
        write_segment(segment, style)
      end

      def segment_style(segment)
        first = absolute_first(segment)
        last = absolute_last(segment)
        {
          token: token_for(segment, first, last),
          selected: covers_range?(segment.selection, first, last),
          matched: covers_range?(segment.highlight, first, last)
        }
      end

      def write_segment(segment, style)
        cell_offset = CursesTextGeometry.column(
          segment.text, segment.first_offset, initial_column: segment.initial_column
        )
        writer = proc { write_segment_text(segment, cell_offset) }
        apply_text_attribute(style[:selected], style[:matched], style[:token], &writer)
      end

      def write_segment_text(segment, cell_offset)
        text = segment.text[segment.first_offset...segment.last]
        width = segment.width - cell_offset
        write_at(segment.row, segment.left + cell_offset, text, width,
                 initial_column: segment.initial_column + cell_offset)
      end

      def token_for(segment, first, last)
        segment.tokens.find do |span|
          span[:start] <= first && span[:finish] >= last
        end
      end

      def absolute_first(segment)
        segment.first + segment.left_column
      end

      def absolute_last(segment)
        segment.last + segment.left_column
      end

      def covers_range?(range, first, last)
        range && first >= range.first && last <= range.last
      end

      def apply_text_attribute(selected, matched, token, &writer)
        return @screen.attron(::Curses::A_REVERSE, &writer) if selected
        return @screen.attron(search_attribute, &writer) if matched

        pair = token && @color_pairs[token[:category]]
        return @screen.attron(::Curses.color_pair(pair), &writer) if pair

        writer.call
      end

      def search_attribute
        @search_pair ? ::Curses.color_pair(@search_pair) : ::Curses::A_STANDOUT
      end

      def write_at(row, column, text, width, initial_column: 0)
        return unless row.between?(0, @screen.maxy - 1) && column.between?(0, @screen.maxx - 1)
        return unless width.positive?

        @screen.setpos(row, column)
        @screen.addstr(CursesTextGeometry.clip(text, width, initial_column:))
      end
    end
  end
end
