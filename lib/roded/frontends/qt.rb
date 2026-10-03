require "qt"
require_relative "qt/key_translator"
require_relative "qt/input_router"
require_relative "qt/editor_pane"
require_relative "qt/splitter_tree"
require_relative "qt/editor_window"
require_relative "qt/clipboard_bridge"
require_relative "qt/buffer_snapshot"
require_relative "qt/ui_dispatcher"

module Roded
  module Frontends
    # Connects the shared editor core to a Qt desktop window.
    class Qt
      UI_COMMAND_ACTIONS = {
        minibuffer_render: :minibuffer,
        picker_render: :picker,
        message: :message,
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
        @input_router = create_input_router
        @input_router.connect(@view)
        @ui_dispatcher.start
      end

      def input_source_id
        :qt
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
      end

      def handle_command(command)
        return enqueue_quit if command.type == :quit

        dispatch_command(command)
      end

      def next_event
        @input_queue.pop
      end

      def run
        @application.trap_signals
        render_initial_layout
        start_core
        @view.show
        @qt_application.exec
        @core_thread.join
      ensure
        @application.restore_signal_handlers
      end

      def close
        @ui_dispatcher.post(:quit)
      end

      def page_size(window_id = nil) = @view.page_size(window_id)

      private

      def create_input_router
        QtInputRouter.new(
          @application,
          QtKeyTranslator.new,
          @clipboard,
          input_source_id,
          page_size_provider: ->(window_id) { @view.page_size(window_id) }
        )
      end

      def render_initial_layout
        @view.render_layout(@application.editor_snapshot)
      end

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
        return command.payload.fetch(:text) if %i[clipboard_write message].include?(command.type)

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
