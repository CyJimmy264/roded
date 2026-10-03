module Roded
  module Frontends
    # Coordinates pane widgets with the current core window tree.
    module QtPaneLayoutOperations
      private

      def prepare_panes(records)
        migrate_single_pane(records)
        bind_panes(records)
        remove_stale_panes(records.keys)
        render_panes(records)
      end

      def mount_editor_tree(tree)
        @splitter_tree.mount(tree) { |id| @panes.fetch(id) }
        @editor_area = @splitter_tree.root
        @panes.each_value { |pane| pane.container.show }
        @editor_area.show
      end
    end
  end
end
