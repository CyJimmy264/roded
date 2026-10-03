module Roded
  # Changes the ratio of the nearest side-by-side split containing a window.
  class WindowLayoutResizer
    def initialize(root)
      @root = root
    end

    def resize(window, amount)
      resize_subtree(@root, window, amount)
    end

    private

    def resize_subtree(node, window, amount)
      return [node, false] unless split_node?(node)
      return [node, false] unless contains?(node, window)

      return resize_split(node, window, amount) if node.direction == :vertical

      resize_child(node, window, amount)
    end

    def resize_split(node, window, amount)
      change = contains?(node.first, window) ? amount : -amount
      ratio = (node.ratio + change).clamp(0.1, 0.9)
      [WindowLayout::Split.new(direction: node.direction, first: node.first, second: node.second, ratio:), true]
    end

    def resize_child(node, window, amount)
      first, resized = resize_subtree(node.first, window, amount)
      return [copy_split(node, first:, second: node.second), true] if resized

      second, resized = resize_subtree(node.second, window, amount)
      return [copy_split(node, first: node.first, second:), true] if resized

      [node, false]
    end

    def copy_split(node, first:, second:)
      WindowLayout::Split.new(direction: node.direction, first:, second:, ratio: node.ratio)
    end

    def contains?(node, target)
      node.equal?(target) || (split_node?(node) && (contains?(node.first, target) || contains?(node.second, target)))
    end

    def split_node?(node)
      node.is_a?(WindowLayout::Split)
    end
  end
end
