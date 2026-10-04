require_relative "cursor_mapper"
require_relative "editor_html_renderer"
require_relative "mouse_input_adapter"
require_relative "layout_spacing"
require_relative "horizontal_scroll_operations"
require_relative "vertical_scroll_operations"
require_relative "document_renderer"

module Roded
  module Frontends
    # Renders one editor view and routes its key events to the core.
    class QtEditorPane
      include QtHorizontalScrollOperations
      include QtVerticalScrollOperations

      attr_reader :container, :editor, :snapshot, :document_renderer

      def initialize(parent, template: nil)
        @container = QWidget.new(parent)
        @layout = QVBoxLayout.new(@container)
        initialize_editor(template)
        configure_editor
        @modeline = QLabel.new(@container)
        QtLayoutSpacing.configure_pane(@container, @layout, @editor, @modeline)
        @layout.add_widget(@editor)
        @layout.add_widget(@modeline)
        @subscribed = false
      end

      def configure_editor
        font = @editor.font
        font.set_family("monospace")
        @editor.set_font(font)
        @editor.set_read_only(true)
        @editor.set_undo_redo_enabled(false)
        @editor.set_context_menu_policy(::Qt::NoContextMenu)
        @editor.set_cursor_width(2)
        @editor.set_mouse_tracking(true)
        @editor.set_line_wrap_mode(::Qt::QTextEdit::NoWrap)
      end

      def bind(window_id, callback, wheel_callback = nil, mouse_callback = nil, horizontal_scroll_callback = nil)
        @window_id = window_id
        @key_callback = callback
        @wheel_callback = wheel_callback
        @horizontal_scroll_callback = horizontal_scroll_callback
        @mouse_callback = mouse_callback
        subscribe_keys
        subscribe_wheel
        subscribe_horizontal_scroll
        @mouse_input.bind(@window_id, @mouse_callback)
      end

      def render(snapshot)
        with_horizontal_scroll_signals_blocked { render_snapshot(snapshot) }
      end

      def render_snapshot(snapshot)
        @snapshot = snapshot
        text = snapshot.fetch(:text).gsub("\r\n", "\n")
        @rendered_text = text
        @mouse_input.update(text:, snapshot:)
        render_text(snapshot, text)
        restore_scroll(snapshot)
        restore_horizontal_scroll(snapshot, text)
        schedule_scroll_restore
        subscribe_layout
        render_modeline(snapshot)
      end

      private

      def initialize_editor(template)
        @editor = QTextEdit.new(@container)
        @document_renderer = QtDocumentRenderer.new(@editor)
        @document_renderer.copy_from(template.document_renderer) if template
        @mouse_input = QtMouseInputAdapter.new(@editor)
      end

      def render_text(snapshot, text)
        @document_renderer.render(snapshot, text)
        QtCursorMapper.place(@editor, snapshot, text,
                             row_position: @document_renderer.row_position(snapshot[:point][:row]))
      end

      def render_modeline(snapshot)
        @modeline.set_text(snapshot[:modeline] || modeline_for(snapshot))
        @modeline.update
        @container.update
      end

      def subscribe_keys
        return if @subscribed || !@key_callback

        @editor.on(:key_press) do |payload|
          @key_callback.call(payload.merge(window_id: @window_id))
        end
        @subscribed = true
      end

      def subscribe_wheel
        return if @wheel_subscribed || !@wheel_callback

        @editor.on(:wheel) do |payload|
          @wheel_callback.call(payload.merge(window_id: @window_id))
        end
        @wheel_subscribed = true
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
