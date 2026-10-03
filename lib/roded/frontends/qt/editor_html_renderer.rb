module Roded
  module Frontends
    # Builds Qt rich text from immutable core snapshots and visual overlays.
    class QtEditorHtmlRenderer
      def initialize(text, snapshot, cursor_marker)
        @lines = text.split("\n", -1)
        @snapshot = snapshot
        @cursor_marker = cursor_marker
        @range = ordered_range(snapshot[:mark], snapshot[:point])
      end

      def render
        content = @lines.each_with_index.map { |line, row| render_line(line, row) }.join("<br>")
        "<pre style=\"white-space: pre; font-family: monospace; margin: 0;\">#{content}</pre>"
      end

      private

      def ordered_range(mark, point)
        return unless mark && point && mark != point

        [mark, point].sort_by { |position| [position[:row], position[:col]] }
      end

      def render_line(line, row)
        cursor_column = cursor_column_for(row, line.length)
        boundaries = line_boundaries(line, row, cursor_column)
        html = boundaries.each_cons(2).map do |first, last|
          marker = cursor_column == first ? @cursor_marker : ""
          marker + render_segment(line, row, first, last)
        end.join
        cursor_column == line.length ? html + @cursor_marker : html
      end

      def cursor_column_for(row, line_length)
        point = @snapshot[:point]
        point[:row] == row ? point[:col].clamp(0, line_length) : nil
      end

      def line_boundaries(line, row, cursor_column)
        columns = [0, line.length, *token_boundaries(row), *overlay_boundaries(line, row)]
        columns << cursor_column if cursor_column
        columns.map { |column| column.clamp(0, line.length) }.uniq.sort
      end

      def token_boundaries(row)
        @snapshot[:tokens]&.[](row).to_a.flat_map { |token| [token[:start], token[:finish]] }
      end

      def overlay_boundaries(line, row)
        [selected_columns(line, row), highlight_columns(line, row)].compact.flatten
      end

      def render_segment(line, row, first, last)
        value = escape_html(line[first...last].to_s)
        style = segment_style(line, row, first, last)
        style ? "<span style=\"#{style}\">#{value}</span>" : value
      end

      def segment_style(line, row, first, last)
        token_style(row, first, last) + overlay_style(line, row, first, last)
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

      def covers?(range, first, last)
        range && first >= range.first && last <= range.last
      end

      def escape_html(text)
        text.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
      end
    end
  end
end
