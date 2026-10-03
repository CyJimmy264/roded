require_relative "tab_expander"

module Roded
  module Frontends
    # Builds Qt rich text from immutable core snapshots and visual overlays.
    class QtEditorHtmlRenderer
      def initialize(text, snapshot)
        @lines = text.split("\n", -1)
        @snapshot = snapshot
        @range = ordered_range(snapshot[:mark], snapshot[:point])
      end

      def render
        blocks = @lines.each_with_index.map { |line, row| render_block(line, row) }.join
        "<div style=\"white-space: pre; font-family: monospace; margin: 0;\">#{blocks}</div>"
      end

      private

      def ordered_range(mark, point)
        return unless mark && point && mark != point

        [mark, point].sort_by { |position| [position[:row], position[:col]] }
      end

      def render_line(line, row)
        cursor_column = cursor_column_for(row, line.length)
        boundaries = line_boundaries(line, row, cursor_column)
        boundaries.each_cons(2).map do |first, last|
          render_segment(line, row, first, last)
        end.join
      end

      def render_block(line, row)
        background = @snapshot[:point]&.fetch(:row) == row ? "background-color: #343a46;" : ""
        content = line.empty? ? render_empty_line(row) : render_line(line, row)
        "<p style=\"margin: 0; padding: 0; white-space: pre; #{background}\">#{content}</p>"
      end

      def render_empty_line(row)
        point = @snapshot[:point]
        return "&nbsp;" unless point && point[:row] == row

        "<span style=\"color: #282c34; background-color: #61afef;\">&nbsp;</span>"
      end

      def cursor_column_for(row, line_length)
        point = @snapshot[:point]
        point[:row] == row ? point[:col].clamp(0, line_length) : nil
      end

      def line_boundaries(line, row, cursor_column)
        columns = [0, line.length, *token_boundaries(row), *overlay_boundaries(line, row)]
        if cursor_column
          caret = caret_column(cursor_column, line.length)
          columns.push(caret, caret + 1)
        end
        columns.map { |column| column.clamp(0, line.length) }.uniq.sort
      end

      def caret_column(cursor_column, line_length)
        return 0 if line_length.zero?

        cursor_column.clamp(0, line_length - 1)
      end

      def token_boundaries(row) = @snapshot[:tokens]&.[](row).to_a.flat_map { |token| [token[:start], token[:finish]] }

      def overlay_boundaries(line, row)
        [selected_columns(line, row), highlight_columns(line, row)].compact.flatten
      end

      def render_segment(line, row, first, last)
        value = escape_html(QtTabExpander.expand(line, first, last))
        style = segment_style(line, row, first, last)
        style ? "<span style=\"#{style}\">#{value}</span>" : value
      end

      def segment_style(line, row, first, last)
        token_style(row, first, last) + overlay_style(line, row, first, last) + caret_style(line, row, first, last)
      end

      def token_style(row, first, last)
        token = @snapshot[:tokens]&.[](row).to_a.find do |span|
          span[:start] <= first && span[:finish] >= last
        end
        token ? "color: #{SyntaxHighlighter::COLORS.fetch(token[:category])};" : ""
      end

      def overlay_style(line, row, first, last)
        range = highlight_columns(line, row)
        return "color: #282c34; background-color: #e5c07b;" if covers?(range, first, last)
        return "background-color: #3e4451;" if covers?(selected_columns(line, row), first, last)

        ""
      end

      def caret_style(line, row, first, last)
        point = @snapshot[:point]
        return "" unless point && point[:row] == row && !line.empty?

        column = point[:col].clamp(0, line.length)
        column = [column - 1, 0].max if column == line.length
        return "" unless column.between?(first, last - 1)

        "color: #282c34; background-color: #61afef;"
      end

      def selected_columns(line, row)
        return unless @range

        range_columns(line, row, @range.first, @range.last)
      end

      def highlight_columns(line, row)
        highlight = @snapshot[:highlight]
        return unless highlight

        range_columns(line, row, highlight[:start], highlight[:finish])
      end

      def range_columns(line, row, first, last)
        return unless row.between?(first[:row], last[:row])

        start_column = row == first[:row] ? first[:col] : 0
        end_column = row == last[:row] ? last[:col] : line.length
        [start_column, end_column.clamp(0, line.length)]
      end

      def covers?(range, first, last) = range && first >= range.first && last <= range.last

      def escape_html(text)
        text.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
      end
    end
  end
end
