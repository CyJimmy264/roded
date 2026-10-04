module Roded
  module Frontends
    # Indexes rendered UTF-16 block lengths for logarithmic cursor positioning.
    class QtDocumentIndex
      def initialize(lines, snapshot)
        @lengths = lines.each_with_index.map { |line, row| self.class.block_length(line, row, snapshot) }
        @tree = [0, *@lengths]
        build_tree
      end

      def self.block_length(line, row, snapshot)
        expanded = QtCursorMapper.expanded_line(line)
        QtCursorMapper.rendered_line_length(line, expanded) +
          QtCursorMapper.end_of_line_marker_length(line, row, snapshot) + 1
      end

      def initialize_copy(other)
        super
        @lengths = @lengths.dup
        @tree = @tree.dup
      end

      def position(row)
        sum = 0
        index = row
        while index.positive?
          sum += @tree.fetch(index)
          index -= index & -index
        end
        sum
      end

      def update(row, length)
        delta = length - @lengths.fetch(row)
        @lengths[row] = length
        index = row + 1
        while index < @tree.length
          @tree[index] += delta
          index += index & -index
        end
      end

      private

      def build_tree
        (1...@tree.length).each do |index|
          parent = index + (index & -index)
          @tree[parent] += @tree[index] if parent < @tree.length
        end
      end
    end
  end
end
