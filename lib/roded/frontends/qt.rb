require "qt"
require_relative "qt/key_translator"
require_relative "qt/input_router"
require_relative "qt/editor_pane"
require_relative "qt/splitter_tree"
require_relative "qt/editor_window"
require_relative "qt/clipboard_bridge"
require_relative "qt/buffer_snapshot"
require_relative "qt/ui_dispatcher"
require_relative "qt/close_guard"

module Roded
  module Frontends
    # Connects the shared editor core to a Qt desktop window.
    class Qt
      UI_COMMAND_ACTIONS = {
        minibuffer_render: :minibuffer,
        picker_render: :picker,
        clipboard_write: :clipboard_write,
        minibuffer_clear: :minibuffer_clear
      }.freeze

      attr_reader :view

      def initialize(application)
        @application = application
        @input_queue = Queue.new
        @qt_application = QApplication.new(0, ["roded"])
        @clipboard = QtClipboardBridge.new
        @view = QtEditorWindow.new
        @ui_dispatcher = QtUiDispatcher.new(@view, @qt_application, @clipboard)
        @close_guard = QtCloseGuard.new(@ui_dispatcher)
        @input_router = QtInputRouter.new(@application, QtKeyTranslator.new, @clipboard, input_source_id)
        @input_router.connect(@view) { @close_guard.mark_pending }
        @ui_dispatcher.start
      end

      def input_source_id
        :qt
      end

      def add_buffer(buffer)
        buffer.add_observer(self)
        render(buffer) if buffer == @application.current_buffer
      end

      def remove_buffer(buffer)
        buffer.remove_observer(self)
      end

      def update(buffer)
        render(buffer) if buffer == @application.current_buffer
      end

      def render(buffer = nil)
        buffer ||= @application.current_buffer
        return unless buffer

        if @application.current_window
          @ui_dispatcher.post(:layout, @application.editor_snapshot)
          return
        end
        @ui_dispatcher.post(:render, QtBufferSnapshot.capture(buffer))
      end

      def display_message(message)
        @ui_dispatcher.post(:message, message.to_s.dup)
        @close_guard.reopen_if_pending
      end

      def handle_command(command)
        if command.type == :quit
          @close_guard.clear
          return enqueue_quit
        end

        result = dispatch_command(command)
        @close_guard.reopen_if_pending
        result
      end

      def next_event
        @input_queue.pop
      end

      def run
        @application.trap_signals
        start_core
        @view.show
        @qt_application.exec
        @core_thread.join
      ensure
        @application.restore_signal_handlers
      end

      def close
        @close_guard.clear
        @ui_dispatcher.post(:quit)
      end

      def page_size(_window_id = nil)
        scroll_bar = @view.editor.vertical_scroll_bar
        [scroll_bar.page_step / [scroll_bar.single_step, 1].max, 1].max
      end

      private

      def handle_render_command(command)
        snapshot = command.payload[:editor_snapshot]
        snapshot ? @ui_dispatcher.post(:layout, snapshot) : render
      end

      def dispatch_command(command)
        return handle_render_command(command) if %i[render move_cursor].include?(command.type)

        action = UI_COMMAND_ACTIONS[command.type]
        @ui_dispatcher.post(action, command_payload(command)) if action
      end

      def command_payload(command)
        return command.payload.dup.freeze if command.type == :minibuffer_render
        return command.payload.fetch(:text) if command.type == :clipboard_write

        command.payload
      end

      def start_core
        @core_thread = Thread.new { @application.run(manage_signals: false) }
      end

      def enqueue_quit
        @input_queue << Event.new(:quit, {})
        @ui_dispatcher.post(:quit)
      end
    end
  end
end
