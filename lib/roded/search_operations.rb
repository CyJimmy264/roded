module Roded
  # Search and line-navigation behavior shared by all frontends.
  module SearchOperations
    def goto_line(value)
      number = Integer(value, 10)
      return display_message("Line number must be positive.") unless number.positive?

      move_to_position((number - 1).clamp(0, current_buffer.lines.length - 1), 0)
    rescue ArgumentError, TypeError
      display_message("Enter a valid line number.")
    end

    def search(query, direction)
      return display_message("Search query is empty.") if query.to_s.empty?

      position = find_match(query.to_s, direction)
      return display_message("No match for '#{query}'.") unless position

      move_to_position(*position, highlight: match_range(position, query))
      display_message("Found '#{query}'.")
    end

    private

    def find_match(query, direction, from: current_window.point, inclusive: false)
      rows = matching_rows(from[:row], direction)
      rows.each do |row|
        line = current_buffer.lines.fetch(row)
        offset = search_offset(row, from, direction, inclusive, line.length)
        next if direction == :backward && offset.negative?

        column = locate_match(line, query, direction, offset)
        return [row, column] if column
      end
      nil
    end

    def matching_rows(row, direction)
      return (row...current_buffer.lines.length).to_a if direction == :forward

      (0..row).to_a.reverse
    end

    def search_offset(row, point, direction, inclusive, line_length)
      return 0 if row != point[:row] && direction == :forward
      return line_length if row != point[:row]
      return point[:col] if inclusive

      point[:col] + (direction == :forward ? 1 : -1)
    end

    def locate_match(line, query, direction, offset)
      folded_line = line.downcase
      folded_query = query.downcase
      direction == :forward ? folded_line.index(folded_query, offset) : folded_line.rindex(folded_query, offset)
    end

    def move_to_position(row, column, highlight: nil)
      current_window.point = { row:, col: column }
      current_buffer.cursor_pos = current_window.point
      current_window.highlight = highlight
      broadcast_command(Command.new(:render, {}))
    end

    def match_range(position, query)
      row, column = position
      { start: { row:, col: column }, finish: { row:, col: column + query.length } }
    end
  end
end
