module Roded
  module Frontends
    # Detects snapshots that differ only by the active cursor position.
    class CursesCursorSnapshotComparison
      def self.call(previous, snapshot)
        new(previous, snapshot).call
      end

      def initialize(previous, snapshot)
        @previous = previous
        @snapshot = snapshot
      end

      def call
        return false unless same_layout? && same_windows?

        active_point_changed?
      end

      private

      def same_layout?
        @previous && @previous[:tree] == @snapshot[:tree] &&
          @previous[:active_window_id] == @snapshot[:active_window_id]
      end

      def same_windows?
        old_windows = windows_by_id(@previous)
        new_windows = windows_by_id(@snapshot)
        return false unless same_window_ids?(old_windows, new_windows)

        old_windows.all? { |id, old_item| stable_window?(id, old_item, new_windows.fetch(id)) }
      end

      def same_window_ids?(old_windows, new_windows)
        old_windows.keys.sort == new_windows.keys.sort
      end

      def stable_window?(id, old_item, item)
        same_presentation?(old_item, item) && old_item[:mark].nil? && stable_point?(id, old_item, item)
      end

      def same_presentation?(old_item, item)
        old_item.except(:point) == item.except(:point)
      end

      def stable_point?(id, old_item, item)
        id == @snapshot[:active_window_id] || old_item[:point] == item[:point]
      end

      def windows_by_id(snapshot)
        snapshot[:windows].to_h { |item| [item[:id], item] }
      end

      def active_point_changed?
        active_id = @snapshot[:active_window_id]
        windows_by_id(@previous).fetch(active_id)[:point] != windows_by_id(@snapshot).fetch(active_id)[:point]
      end
    end
  end
end
