module Roded
  module Frontends
    # Mounts nested Qt splitters while reusing them as the layout changes.
    class QtSplitterTree
      attr_reader :root

      def initialize(parent, layout)
        @parent = parent
        @layout = layout
        @pool = []
        @tree = nil
        @mounted_widgets = {}
      end

      def mount(tree, &pane_for)
        widgets = widgets_for(tree, &pane_for)
        return if tree == @tree && same_widgets?(widgets)

        @layout.remove_widget(@root) if @root
        release_root
        @root = build(tree) { |id| pane_for.call(id) }
        @layout.add_widget(@root)
        @tree = tree
        @mounted_widgets = widgets
      end

      def mount_single(widget)
        return if @tree.nil? && @root.equal?(widget)

        @layout.remove_widget(@root) if @root
        release_root
        @root = widget
        @layout.add_widget(@root)
        @tree = nil
        @mounted_widgets = { single: widget }
      end

      private

      def build(tree, &pane_for)
        return pane_for.call(tree.fetch(:window_id)).container if tree[:window_id]

        splitter_for(tree, &pane_for)
      end

      def widgets_for(tree, &pane_for)
        return { tree.fetch(:window_id) => pane_for.call(tree.fetch(:window_id)).container } if tree[:window_id]

        widgets_for(tree[:first], &pane_for).merge(widgets_for(tree[:second], &pane_for))
      end

      def same_widgets?(widgets)
        widgets.length == @mounted_widgets.length && widgets.all? do |id, widget|
          @mounted_widgets[id]&.equal?(widget)
        end
      end

      def release_root
        return unless @root
        return release(@root) if @root.is_a?(QSplitter)

        @root.hide
        @root.set_parent(@parent)
      end

      def splitter_for(tree, &pane_for)
        splitter = @pool.pop || QSplitter.new(@parent)
        splitter.orientation = tree[:direction] == :vertical ? ::Qt::Horizontal : ::Qt::Vertical
        first = build(tree[:first]) { |id| pane_for.call(id) }
        second = build(tree[:second]) { |id| pane_for.call(id) }
        splitter.add_widget(first)
        splitter.add_widget(second)
        apply_split_sizes(splitter, tree.fetch(:ratio, 0.5))
        splitter
      end

      def apply_split_sizes(splitter, ratio)
        first = (ratio.clamp(0.05, 0.95) * 1000).round
        splitter.set_stretch_factor(0, 1)
        splitter.set_stretch_factor(1, 1)
        splitter.set_sizes([first, 1000 - first])
      end

      def release(widget)
        return unless widget.is_a?(QSplitter)

        children = widget.count.times.map { |index| widget.widget(index) }
        children.each do |child|
          release(child)
          child.set_parent(@parent)
        end
        widget.hide
        widget.set_parent(@parent)
        @pool << widget
      end
    end
  end
end
