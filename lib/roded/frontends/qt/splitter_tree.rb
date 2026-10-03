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
      end

      def mount(tree, &pane_for)
        return if tree == @tree

        @layout.remove_widget(@root) if @root
        release(@root)
        @root = build(tree) { |id| pane_for.call(id) }
        @layout.add_widget(@root)
        @tree = tree
      end

      def mount_single(widget)
        @layout.remove_widget(@root) if @root
        release(@root)
        @root = widget
        @layout.add_widget(@root)
        @tree = nil
      end

      private

      def build(tree, &pane_for)
        return pane_for.call(tree.fetch(:window_id)).container if tree[:window_id]

        splitter_for(tree, &pane_for)
      end

      def splitter_for(tree, &pane_for)
        splitter = @pool.pop || QSplitter.new(@parent)
        splitter.orientation = tree[:direction] == :vertical ? Qt::Horizontal : Qt::Vertical
        splitter.add_widget(build(tree[:first]) { |id| pane_for.call(id) })
        splitter.add_widget(build(tree[:second]) { |id| pane_for.call(id) })
        splitter.set_stretch_factor(0, 1)
        splitter.set_stretch_factor(1, 1)
        splitter
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
