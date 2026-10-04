module Roded
  module Benchmarking
    # Character-wise reference, independent of the editor's regular-expression movement.
    class LatencyWordCursor
      def initialize(lines, point)
        @lines = lines
        @row, @col = point.values_at("row", "col")
      end

      def forward
        step_forward until at_end? || word?(@lines[@row][@col])
        step_forward while !at_end? && word?(@lines[@row][@col])
        position
      end

      def backward
        step_backward until at_start? || word?(preceding_character)
        step_backward while !at_start? && word?(preceding_character)
        position
      end

      private

      def word?(character) = character&.match?(/\A[[:alnum:]_]\z/)

      def at_end? = @row == @lines.length - 1 && @col == @lines[@row].length

      def at_start? = @row.zero? && @col.zero?

      def preceding_character = @col.positive? ? @lines[@row][@col - 1] : nil

      def position = { "row" => @row, "col" => @col }

      def step_forward
        if @col < @lines[@row].length
          @col += 1
        else
          @row += 1
          @col = 0
        end
      end

      def step_backward
        if @col.positive?
          @col -= 1
        else
          @row -= 1
          @col = @lines[@row].length
        end
      end
    end
  end
end
