require_relative "core_application"
require_relative "null_frontend"

module Roded
  module Benchmarking
    # Owns fresh editor state for each sample; resets are outside the timed interval.
    class Workspace
      attr_reader :application, :fixture, :frontend, :base_windows, :documents

      def initialize(layer:, fixture:, buffer_count:, window_count:)
        @fixture = fixture
        @application = (layer == "core" ? CoreApplication : Application).new
        @documents = build_documents(buffer_count)
        @base_windows = Array.new(window_count) { Window.new(documents.first) }
        @tracked_windows = base_windows.dup
        reset
        @frontend = build_frontend(layer)
        connect_frontend
      end

      def window = application.current_window

      def buffer = application.current_buffer

      def middle = fixture.line_count / 2

      def page_size = frontend.page_size

      def reset
        discard_extra_windows
        application.current_window = base_windows.first
        restore_buffers
        documents.first.load_text(fixture.text)
        restore_layout
        base_windows.each { |view| position(view) }
      end

      def position(view = window, row: middle, col: 12, origin: middle - 10, left: 0)
        view.point = { row:, col: }
        view.mark = nil
        view.top_line = origin
        view.left_column = left
      end

      def dispatch(type, payload = {})
        context = { window_id: window.object_id, source_id: :benchmark, page_size: }
        application.handle_event(InputEvent.new(type, context.merge(payload)))
        @tracked_windows |= application.windows if type.to_s.start_with?("split_")
      end

      def render
        application.publish_ui_update(UIUpdate.new(:render, {}))
        frontend.finish
      end

      def close = frontend&.close

      private

      def connect_frontend
        application.add_frontend(frontend)
        frontend.show if frontend.respond_to?(:show)
        frontend.finish
      end

      def build_documents(count)
        Array.new(count) do |index|
          Buffer.new("bench-#{index}").tap do |buffer|
            buffer.major_mode = fixture.mode
            buffer.load_text(fixture.text)
            application.add_buffer(buffer)
          end
        end
      end

      def restore_buffers
        base_windows.each { |view| view.buffer = documents.first unless view.buffer.equal?(documents.first) }
      end

      def restore_layout
        application.session.window_layout = WindowLayout.new(base_windows.first)
        base_windows.drop(1).each do |view|
          application.session.window_layout.split(base_windows.first, view, :vertical)
        end
      end

      def build_frontend(layer)
        case layer
        when "core", "application" then NullFrontend.new
        when "curses"
          require_relative "curses_frontend"
          CursesFrontend.new
        when "qt"
          require_relative "qt_frontend"
          QtFrontend.new(application)
        else raise ArgumentError, "unknown layer: #{layer}"
        end
      end

      def discard_extra_windows
        @tracked_windows.each do |view|
          next if base_windows.include?(view)

          # A benchmark reset must not accumulate closed views between repetitions.
          documents.each { |document| document.remove_edit_observer(view) }
        end
        @tracked_windows = base_windows.dup
      end
    end
  end
end
