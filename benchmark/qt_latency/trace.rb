module Roded
  module Benchmarking
    # Small benchmark-only hooks; no event-loop pumping or dispatcher draining.
    class LatencyTrace
      def initialize(frontend)
        @frontend = frontend
        @mutex = Mutex.new
        @sequence = 0
      end

      def key_received(key)
        @mutex.synchronize do
          raise "received another key before the previous frame" if @pending

          @sequence += 1
          @pending = { sequence: @sequence, key:, phases_ns: { input_received: now } }
          @target = nil
        end
      end

      def mark(phase)
        @mutex.synchronize { @pending[:phases_ns][phase] ||= now if @pending }
      end

      def snapshot_posted(snapshot)
        @mutex.synchronize do
          next unless @pending

          @pending[:phases_ns][:snapshot_posted] = now
          @target = target(snapshot)
        end
      end

      def widget_started(snapshot)
        @mutex.synchronize do
          @pending[:phases_ns][:widget_started] = now if @pending && @target == target(snapshot)
        end
      end

      def rendered(snapshot)
        record = @mutex.synchronize do
          next unless @pending && @pending[:phases_ns][:widget_started] && @target == target(snapshot)

          @pending[:phases_ns][:widget_finished] = now
          @pending.tap { @pending = nil }
        end
        emit("rendered", snapshot, record) if record
      end

      def emit(type, snapshot, record = {})
        editor = @frontend.view.editor
        active = snapshot.fetch(:windows).find { |item| item[:id] == snapshot[:active_window_id] }
        geometry = caret_geometry(editor)
        raise "caret is outside the visible viewport" unless geometry[:visible]

        puts JSON.generate(record.merge(type:, caret: geometry, **content(active), **view_state(editor, type)))
        $stdout.flush
      end

      private

      def view_state(editor, type)
        { horizontal_scroll: editor.horizontal_scroll_bar.value }.merge(ready_metadata(type))
      end

      def ready_metadata(type)
        return {} unless type == "ready"

        dispatcher = @frontend.instance_variable_get(:@ui_dispatcher)
        timer = dispatcher.instance_variable_get(:@timer)
        { dispatcher_interval_ms: timer.interval, dispatcher_single_shot: timer.is_single_shot }
      end

      def target(snapshot)
        active = snapshot.fetch(:windows).find { |item| item[:id] == snapshot[:active_window_id] }
        [active[:id], active[:point], active[:text].object_id]
      end

      def content(active)
        { point: active.fetch(:point), line: active.fetch(:lines)[active[:point][:row]] }
      end

      def caret_geometry(editor)
        origin = editor.viewport.map_to_global(::Qt::QPointF.new).to_point
        rect = editor.cursor_rect
        { x: (origin.x + rect.x).round, y: (origin.y + rect.y).round,
          width: caret_width(editor), height: rect.height,
          visible: visible?(rect, editor) }
      end

      def visible?(rect, editor) = rect.y >= 0 && rect.y + rect.height <= editor.viewport.height

      def caret_width(editor) = [editor.font_metrics.horizontal_advance(" "), 4].max

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
    end
  end
end
