module Roded
  # Represents nested splits and calculates their non-overlapping rectangles.
  class WindowLayout
    Split = Data.define(:direction, :first, :second)
    Rectangle = Data.define(:x, :y, :width, :height)

    def initialize(window)
      @root = window
    end

    def split(window, new_window, direction)
      raise ArgumentError, "invalid split direction" unless %i[horizontal vertical].include?(direction)

      replaced = false
      @root = replace(@root, window) do
        replaced = true
        Split.new(direction:, first: window, second: new_window)
      end
      raise ArgumentError, "window is not in this layout" unless replaced
    end

    def remove(window)
      @root, removed = prune(@root, window)
      removed
    end

    def keep(window)
      @root = window
    end

    def windows
      leaves(@root)
    end

    def rectangles(width, height)
      place(@root, Rectangle.new(x: 0, y: 0, width:, height:))
    end

    def snapshot_tree
      serialize(@root)
    end

    private

    def replace(node, target, &replacement)
      return replacement.call if node.equal?(target)
      return node unless split_node?(node)

      Split.new(
        direction: node.direction,
        first: replace(node.first, target, &replacement),
        second: replace(node.second, target, &replacement)
      )
    end

    def prune(node, target)
      return [nil, true] if node.equal?(target)
      return [node, false] unless split_node?(node)

      first, removed = prune(node.first, target)
      return [replace_branch(node, first, node.second), true] if removed

      second, removed = prune(node.second, target)
      return [replace_branch(node, node.first, second), true] if removed

      [node, false]
    end

    def replace_branch(node, first, second)
      return second unless first
      return first unless second

      Split.new(direction: node.direction, first:, second:)
    end

    def leaves(node)
      return [] unless node
      return [node] unless split_node?(node)

      leaves(node.first) + leaves(node.second)
    end

    def place(node, rectangle)
      return [] unless node
      return [[node, rectangle]] unless split_node?(node)

      first_rect, second_rect = divide(rectangle, node.direction)
      place(node.first, first_rect) + place(node.second, second_rect)
    end

    def divide(rectangle, direction)
      direction == :vertical ? divide_columns(rectangle) : divide_rows(rectangle)
    end

    def divide_columns(rectangle)
      first_width = rectangle.width / 2
      first = Rectangle.new(x: rectangle.x, y: rectangle.y, width: first_width, height: rectangle.height)
      second = Rectangle.new(x: rectangle.x + first_width, y: rectangle.y,
                             width: rectangle.width - first_width, height: rectangle.height)
      [first, second]
    end

    def divide_rows(rectangle)
      first_height = rectangle.height / 2
      first = Rectangle.new(x: rectangle.x, y: rectangle.y, width: rectangle.width, height: first_height)
      second = Rectangle.new(x: rectangle.x, y: rectangle.y + first_height,
                             width: rectangle.width, height: rectangle.height - first_height)
      [first, second]
    end

    def split_node?(node)
      node.is_a?(Split)
    end

    def serialize(node)
      return { window_id: node.object_id }.freeze unless split_node?(node)

      {
        direction: node.direction,
        first: serialize(node.first),
        second: serialize(node.second)
      }.freeze
    end
  end
end
