require_relative "editor_pane"
require_relative "echo_area"
require_relative "splitter_tree"
require_relative "pane_layout_operations"
require_relative "window_theme"
require_relative "window_focus_operations"

module Roded
  module Frontends
    # Presents editor snapshots in a tree of read-only Qt panes.
    class QtEditorWindow
      include QtPaneLayoutOperations
      include QtWindowFocusOperations

      attr_reader :window, :editor, :editor_area

      def initialize
        @window = QWidget.new
        @window.set_window_title("Roded")
        @content_host = QWidget.new(@window)
        @content_layout = QVBoxLayout.new(@content_host)
        @content_host.set_layout(@content_layout)
        @echo_area = QtEchoArea.new(@window)
        initialize_panes
        build_layout
        QtWindowTheme.apply(@window)
      end

      def on_key_press(&callback) = bind_callback(:key_callback, callback)

      def on_wheel(&callback) = bind_callback(:wheel_callback, callback)

      def on_mouse(&callback) = bind_callback(:mouse_callback, callback)

      def on_close(&) = @window.on(:close, &)

      def on_resize(&) = @window.on(:resize, &)

      def show(_payload = nil)
        @window.resize(960, 640)
        @window.show
        @editor_area&.show
        @panes.each_value { |pane| pane.container.show }
        @window.activate_window
        focus_editor_after_show
      end

      def render(snapshot)
        pane = pane_for(:single)
        bind_pane(:single, pane)
        pane.render(snapshot)
        @splitter_tree.mount_single(pane.container)
        @editor_area = pane.container
        @editor_area.show
        @editor = pane.editor
        @editor.set_focus
      end

      def render_layout(snapshot)
        records = snapshot[:windows].to_h { |item| [item[:id], item] }
        prepare_panes(records)
        mount_editor_tree(snapshot[:tree])
        activate_editor(snapshot[:active_window_id])
      end

      def render_minibuffer(payload) = @echo_area.render_minibuffer(payload)
      def render_picker(payload) = @echo_area.render_picker(payload)
      def clear_minibuffer = @echo_area.clear
      def display_message(message) = @echo_area.display(message)
      def close = @window.hide

      private

      def initialize_panes
        @panes = {}
        @pane_pool = []
        @splitter_tree = QtSplitterTree.new(@window, @content_layout)
        @editor = nil
        @editor_area = nil
        @active_window_id = nil
      end

      def build_layout
        @window_layout = QVBoxLayout.new(@window)
        @window.set_layout(@window_layout)
        @window_layout.add_widget(@content_host)
        @window_layout.add_widget(@echo_area.widget)
      end

      def pane_for(id)
        @panes[id] ||= @pane_pool.pop || QtEditorPane.new(@window)
      end

      def migrate_single_pane(records)
        return unless @panes.key?(:single) && !records.key?(:single) && records.any?

        @panes[records.keys.first] = @panes.delete(:single)
      end

      def bind_panes(records)
        records.each_key { |id| bind_pane(id, pane_for(id)) }
      end

      def bind_pane(id, pane)
        pane.bind(id, @key_callback, @wheel_callback, @mouse_callback)
      end

      def bind_callback(name, callback)
        instance_variable_set("@#{name}", callback)
        @panes.each { |id, pane| bind_pane(id, pane) }
      end

      def render_panes(records)
        records.each { |id, item| @panes.fetch(id).render(item) }
      end

      def remove_stale_panes(active_ids)
        (@panes.keys - active_ids).each do |id|
          pane = @panes.delete(id)
          pane.container.hide
          pane.container.set_parent(@window)
          @pane_pool << pane
        end
      end

      def activate_editor(active_id)
        return unless @panes.key?(active_id)

        @editor = @panes.fetch(active_id).editor
        @editor.set_focus if active_id != @active_window_id
        @active_window_id = active_id
      end
    end
  end
end
