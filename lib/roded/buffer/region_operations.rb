module Roded
  # Extracts and deletes selections expressed in logical row/column positions.
  module BufferRegionOperations
    def region_text(start_position, end_position)
      start_position, end_position = ordered_positions(start_position, end_position)
      return "" if start_position == end_position

      first_row, first_col = start_position.values_at(:row, :col)
      last_row, last_col = end_position.values_at(:row, :col)
      region_lines(first_row, first_col, last_row, last_col).join(@line_ending)
    end

    def delete_region(start_position, end_position) # rubocop:disable Naming/PredicateMethod -- editor commands use imperative names
      return false if readonly

      start_position, end_position = ordered_positions(start_position, end_position)
      return false if start_position == end_position

      first_row, first_col = start_position.values_at(:row, :col)
      last_row, last_col = end_position.values_at(:row, :col)
      record_edit(first_row, last_row - first_row + 1, 1) do
        delete_region_lines(first_row, first_col, last_row, last_col)
      end
      true
    end

    private

    def ordered_positions(first, second)
      positions = [first, second].map do |position|
        row = position.fetch(:row, 0).to_i.clamp(0, @lines.length - 1)
        col = position.fetch(:col, 0).to_i.clamp(0, @lines[row].length)
        { row:, col: }
      end
      positions.sort_by { |position| [position[:row], position[:col]] }
    end

    def region_lines(first_row, first_col, last_row, last_col)
      return [@lines[first_row][first_col...last_col].to_s] if first_row == last_row

      [@lines[first_row][first_col..].to_s, *@lines[(first_row + 1)...last_row], @lines[last_row][0...last_col].to_s]
    end

    def delete_region_lines(first_row, first_col, last_row, last_col)
      prefix = @lines[first_row][0...first_col]
      suffix = @lines[last_row][last_col..].to_s
      @lines[first_row..last_row] = [prefix + suffix]
      @cursor_pos = { row: first_row, col: first_col }
    end
  end
end
