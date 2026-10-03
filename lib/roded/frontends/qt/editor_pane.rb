require_relative "cursor_mapper"
require_relative "editor_html_renderer"

module Roded
  module Frontends
    # Renders one editor view and routes its key events to the core.
    class QtEditorPane
      attr_reader :container, :editor

      def initialize(parent)
        @container = QWidget.new(parent)
        @layout = QVBoxLayout.new(@container)
        @container.set_layout(@layout)
        @editor = QTextEdit.new(@container)
        configure_editor
        @modeline = QLabel.new(@container)
        @layout.add_widget(@editor)
        @layout.add_widget(@modeline)
        @subscribed = false
      end

      def configure_editor
        @editor.set_read_only(true)
        @editor.set_undo_redo_enabled(false)
        @editor.set_context_menu_policy(::Qt::NoContextMenu)
        @editor.set_cursor_width(2)
        # TODO(qt): HACK — qt 0.1.9 omits QTextEdit::LineWrapMode constants.
        # Workaround: use the documented NoWrap enum value 0.
        # Generate LineWrapMode constants in qt, then replace this value with NoWrap.
        @editor.set_line_wrap_mode(0)
      end

      def bind(window_id, callback, wheel_callback = nil)
        @window_id = window_id
        @key_callback = callback
        @wheel_callback = wheel_callback
        subscribe_keys
        subscribe_wheel
      end

      def render(snapshot)
        @snapshot = snapshot
        text = snapshot.fetch(:text).gsub("\r\n", "\n")
        render_text(snapshot, text)
        restore_scroll(snapshot)
        schedule_scroll_restore
        subscribe_layout
        render_modeline(snapshot)
      end

      private

      def render_text(snapshot, text)
        marker = QtCursorMapper.marker_for(text)
        snapshot = snapshot.merge(cursor_marker: marker)
        @editor.set_html(QtEditorHtmlRenderer.new(text, snapshot, marker).render)
        QtCursorMapper.place(@editor, snapshot, text)
      end

      def render_modeline(snapshot)
        @modeline.set_text(snapshot[:modeline] || modeline_for(snapshot))
        @modeline.repaint
        @container.repaint
      end

      def subscribe_keys
        return if @subscribed || !@key_callback

        @editor.on(:key_press) do |payload|
          @key_callback.call(payload.merge(window_id: @window_id))
        end
        @subscribed = true
      end

      def subscribe_layout
        return if @layout_subscribed

        @editor.on(:resize) { restore_scroll(@snapshot) if @snapshot }
        @layout_subscribed = true
      end

      def subscribe_wheel
        return if @wheel_subscribed || !@wheel_callback

        @editor.on(:wheel) do |payload|
          @wheel_callback.call(payload.merge(window_id: @window_id))
        end
        @wheel_subscribed = true
      end

      def restore_scroll(snapshot)
        scroll_bar = @editor.vertical_scroll_bar
        top_line = visible_origin(snapshot)
        scroll_bar.set_value(top_line * scroll_bar.single_step)
        @editor.viewport.repaint
      end

      def visible_origin(snapshot)
        origin = snapshot.fetch(:top_line, 0).to_i
        point_row = snapshot.fetch(:point).fetch(:row).to_i
        scroll_bar = @editor.vertical_scroll_bar
        page_size = scroll_bar.page_step / [scroll_bar.single_step, 1].max
        return point_row if point_row < origin
        return point_row - page_size + 1 if page_size.positive? && point_row >= origin + page_size

        origin
      end

      def schedule_scroll_restore
        return if @scroll_timer&.is_active

        @scroll_timer ||= QTimer.new(@editor)
        @scroll_timer.set_single_shot(true)
        @scroll_timer.connect("timeout") { |_payload| restore_scroll(@snapshot) }
        @scroll_timer.set_interval(0)
        @scroll_timer.start
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
