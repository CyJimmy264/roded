require_relative "cursor_mapper"
require_relative "editor_html_renderer"

module Roded
  module Frontends
    # Renders one editor view and routes its key events to the core.
    class QtEditorPane
      attr_reader :container, :editor

      def initialize(parent)
        @container = QWidget.new(parent)
        layout = QVBoxLayout.new(@container)
        @editor = QTextEdit.new(@container)
        @editor.set_read_only(true)
        @editor.set_undo_redo_enabled(false)
        # TODO(qt): HACK — qt 0.1.9 omits QTextEdit::LineWrapMode constants.
        # Workaround: use the documented NoWrap enum value 0.
        # Generate LineWrapMode constants in qt, then replace this value with NoWrap.
        @editor.set_line_wrap_mode(0)
        @modeline = QLabel.new(@container)
        layout.add_widget(@editor)
        layout.add_widget(@modeline)
        @subscribed = false
      end

      def bind(window_id, callback)
        @window_id = window_id
        @key_callback = callback
        subscribe_keys
      end

      def render(snapshot)
        text = snapshot.fetch(:text).gsub("\r\n", "\n")
        marker = QtCursorMapper.marker_for(text)
        snapshot = snapshot.merge(cursor_marker: marker)
        @editor.set_html(QtEditorHtmlRenderer.new(text, snapshot, marker).render)
        QtCursorMapper.place(@editor, snapshot, text)
        @modeline.set_text(snapshot[:modeline] || modeline_for(snapshot))
      end

      private

      def subscribe_keys
        return if @subscribed || !@key_callback

        @editor.on(:key_press) do |payload|
          @key_callback.call(payload.merge(window_id: @window_id))
        end
        @subscribed = true
      end

      def modeline_for(snapshot)
        point = snapshot.fetch(:point)
        active = snapshot[:active] ? "--" : "  "
        modified = snapshot[:modified] ? " *" : ""
        readonly = snapshot[:readonly] ? " RO" : ""
        mode = snapshot[:mode] || :plain
        "#{active} #{snapshot.fetch(:name)}#{modified}#{readonly}  #{mode}  #{point[:row] + 1}:#{point[:col] + 1}"
      end
    end
  end
end
