module Roded
  module Frontends
    # Computes selected and highlighted character ranges for a rich-text row.
    module QtEditorOverlayRanges
      private

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
    end
  end
end
