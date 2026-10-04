module Roded
  module Frontends
    # Coordinates pane widgets with the current core window tree.
    module QtPaneLayoutOperations
      def page_size(window_id = @active_window_id)
        pane = @panes[window_id] || @panes[@active_window_id] || @panes[:single]
        return 1 unless pane

        scroll_bar = pane.editor.vertical_scroll_bar
        [scroll_bar.page_step / [scroll_bar.single_step, 1].max, 1].max
      end

      private

      def pane_for(id, snapshot = nil)
        @panes[id] ||= @pane_pool.pop || build_pane(snapshot)
      end

      def build_pane(snapshot)
        template = @panes.values.find do |pane|
          snapshot&.[](:lines) && pane.snapshot && pane.snapshot[:lines].equal?(snapshot[:lines])
        end
        QtEditorPane.new(@window, template:)
      end

      def migrate_single_pane(records)
        return unless @panes.key?(:single) && !records.key?(:single) && records.any?

        @panes[records.keys.first] = @panes.delete(:single)
      end

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
