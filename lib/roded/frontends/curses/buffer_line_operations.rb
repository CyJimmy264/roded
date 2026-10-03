module Roded
  module Frontends
    # Finds text ranges that need syntax, region, or search styling.
    module CursesBufferLineOperations
      private

      def draw_buffer_line(context)
        data = line_render_data(context)
        boundaries = line_boundaries(
          data[:text], data[:tokens], data[:selection], data[:highlight], context.left_column
        )
        boundaries.each_cons(2) { |first, last| render_line_segment(context, data, first, last) }
      end

      def line_render_data(context)
        {
          text: visible_line(context),
          initial_column: line_initial_column(context),
          tokens: line_tokens(context),
          selection: line_selection(context),
          highlight: line_highlight(context)
        }
      end

      def visible_line(context)
        context.line[context.left_column..].to_s
      end

      def line_initial_column(context)
        CursesTextGeometry.column(context.line, context.left_column)
      end

      def line_tokens(context)
        context.item[:tokens]&.[](context.buffer_row).to_a
      end

      def line_selection(context)
        selection_columns(context.item, context.buffer_row, context.line.length)
      end

      def line_highlight(context)
        highlight_columns(context.item, context.buffer_row, context.line.length)
      end

      def render_line_segment(context, data, first, last)
        segment = CursesRenderContext::StyledSegment.new(
          row: context.screen_row, left: context.left, text: data[:text], first_offset: first, last:,
          width: context.width, tokens: data[:tokens], selection: data[:selection],
          highlight: data[:highlight], left_column: context.left_column,
          initial_column: data[:initial_column]
        )
        write_styled_segment(segment)
      end

      def line_boundaries(text, tokens, selection, highlight, left_column)
        boundaries = [0, text.length]
        add_token_boundaries(boundaries, tokens, left_column)
        add_range_boundaries(boundaries, selection, left_column)
        add_range_boundaries(boundaries, highlight, left_column)
        boundaries.map { |column| column.clamp(0, text.length) }.uniq.sort
      end

      def add_token_boundaries(boundaries, tokens, left_column)
        tokens.each do |token|
          boundaries.push(token[:start] - left_column, token[:finish] - left_column)
        end
      end

      def add_range_boundaries(boundaries, range, left_column)
        boundaries.concat(range.map { |column| column - left_column }) if range
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
        [start_column, [end_column, line_length].min]
      end
    end
  end
end
