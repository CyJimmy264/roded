require "qt"
require_relative "qt/key_translator"
require_relative "qt/editor_window"
require_relative "qt/ui_dispatcher"

module Roded
  module Frontends
    # Connects the shared editor core to a single Qt desktop window.
    class Qt
      attr_reader :view

      def initialize(application)
        @application = application
        @input_queue = Queue.new
        @key_translator = QtKeyTranslator.new
        @qt_application = QApplication.new(0, ["roded"])
        @view = QtEditorWindow.new
        @ui_dispatcher = QtUiDispatcher.new(@view, @qt_application)
        configure_events
        start_ui_dispatcher
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

        @ui_dispatcher.post(:render, buffer_snapshot(buffer))
      end

      def display_message(message)
        @ui_dispatcher.post(:message, message.to_s.dup)
      end

      def handle_command(command)
        case command.type
        when :render, :move_cursor
          render
        when :minibuffer_render
          @ui_dispatcher.post(:minibuffer, command.payload.dup.freeze)
        when :minibuffer_clear
          @ui_dispatcher.post(:minibuffer_clear)
        when :quit
          enqueue_quit
        end
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
        @ui_dispatcher.post(:quit)
      end

      def page_size
        [@view.editor.height / 20, 1].max
      end

      private

      def configure_events
        @view.on_key_press { |payload| enqueue_key(payload) }
        @view.on_close do |_payload|
          @application.push_event(Event.new(:quit, {}))
          :consume
        end
        @view.on_resize { |_payload| @application.push_event(Event.new(:resize, {})) }
      end

      def enqueue_key(payload)
        key = @key_translator.translate(payload)
        @application.push_event(Event.new(:key, { key: key, source_id: input_source_id })) if key
        :consume
      end

      def start_ui_dispatcher
        @ui_dispatcher.start
      end

      def start_core
        @core_thread = Thread.new { @application.run(manage_signals: false) }
      end

      def enqueue_quit
        @input_queue << Event.new(:quit, {})
        @ui_dispatcher.post(:quit)
      end

      def buffer_snapshot(buffer)
        point = buffer.cursor_pos.dup.freeze
        name = buffer.filename || buffer.name || "*scratch*"
        {
          text: buffer.to_s.dup.freeze,
          row: point.fetch(:row),
          col: point.fetch(:col),
          modeline: "-- Roded -- #{name}  #{point.fetch(:row) + 1}:#{point.fetch(:col) + 1}"
        }.freeze
      end
    end
  end
end
