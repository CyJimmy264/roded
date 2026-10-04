module Roded
  # Reuses immutable tree and leaf snapshots until the layout changes.
  module WindowLayoutSnapshotOperations
    def windows
      @windows ||= leaves(@root).freeze
    end

    def snapshot_tree
      @snapshot_tree ||= serialize(@root)
    end

    private

    def invalidate_snapshots
      @windows = nil
      @snapshot_tree = nil
    end

    def leaves(node)
      return [] unless node
      return [node] unless node.is_a?(WindowLayout::Split)

      leaves(node.first) + leaves(node.second)
    end

    def serialize(node)
      return { window_id: node.object_id }.freeze unless node.is_a?(WindowLayout::Split)

      { direction: node.direction, first: serialize(node.first), second: serialize(node.second),
        ratio: node.ratio }.freeze
    end
  end
end
