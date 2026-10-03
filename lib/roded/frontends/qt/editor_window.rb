require_relative "editor_pane"
require_relative "echo_area"
require_relative "splitter_tree"

module Roded
  module Frontends
    # Presents editor snapshots in a tree of read-only Qt panes.
    class QtEditorWindow
      attr_reader :window, :editor, :editor_area

      def initialize
        @window = QWidget.new
        @window.set_window_title("Roded")
        @content_host = QWidget.new(@window)
        @content_layout = QVBoxLayout.new(@content_host)
        @echo_area = QtEchoArea.new(@window)
        initialize_panes
        build_layout
        apply_theme
      end

      def on_key_press(&callback)
        @key_callback = callback
        @panes.each { |id, pane| pane.bind(id, callback) }
      end

      def on_close(&)
        @window.on(:close, &)
      end

      def on_resize(&)
        @window.on(:resize, &)
      end

      def show(_payload = nil)
        @window.resize(960, 640)
        @window.show
        @editor&.set_focus
      end

      def render(snapshot)
        pane = pane_for(:single)
        pane.bind(:single, @key_callback)
        pane.render(snapshot)
        @splitter_tree.mount_single(pane.container)
        @editor_area = pane.container
        @editor = pane.editor
        @editor.set_focus
      end

      def render_layout(snapshot)
        records = snapshot[:windows].to_h { |item| [item[:id], item] }
        migrate_single_pane(records)
        bind_panes(records)
        remove_stale_panes(records.keys)
        render_panes(records)
        @splitter_tree.mount(snapshot[:tree]) { |id| @panes.fetch(id) }
        @editor_area = @splitter_tree.root
        activate_editor(snapshot[:active_window_id])
      end

      def render_minibuffer(payload) = @echo_area.render_minibuffer(payload)

      def render_picker(payload) = @echo_area.render_picker(payload)

      def clear_minibuffer = @echo_area.clear

      def display_message(message) = @echo_area.display(message)

      def close
        @window.hide
      end

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
        layout = QVBoxLayout.new(@window)
        layout.add_widget(@content_host)
        layout.add_widget(@echo_area.widget)
      end

      def pane_for(id)
        @panes[id] ||= @pane_pool.pop || QtEditorPane.new(@window)
      end

      def migrate_single_pane(records)
        return unless @panes.key?(:single) && !records.key?(:single) && records.any?

        @panes[records.keys.first] = @panes.delete(:single)
      end

      def bind_panes(records)
        records.each_key { |id| pane_for(id).bind(id, @key_callback) }
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

      def apply_theme
        @window.set_style_sheet(
          "QWidget { background: #292b34; color: #bbc2cf; } " \
          "QTextEdit { background: #282c34; color: #bbc2cf; border: 0; " \
          "selection-background-color: #3e4451; } QLabel { padding: 4px; }"
        )
      end
    end
  end
end
