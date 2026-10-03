module Roded
  # Produces immutable snapshots and propagates edits to other views.
  module EditorSnapshotOperations
    def editor_snapshot
      {
        tree: session.window_layout.snapshot_tree,
        active_window_id: current_window&.object_id,
        windows: windows.map { |window| window_snapshot(window) }.freeze
      }.freeze
    end

    private

    def activate_window(window)
      self.current_window = window
      render_active_window
    end

    def render_active_window
      publish_ui_update(UIUpdate.new(:render, {}))
    end

    def window_snapshot(window)
      buffer = window.buffer
      lines = buffer.lines
      mode = buffer.mode
      {
        id: window.object_id,
        text: buffer.to_s.dup.freeze,
        lines: lines.map { |line| line.dup.freeze }.freeze,
        mode: mode,
        tokens: @syntax_highlighter.spans(mode, lines)
      }.merge(window_state_snapshot(window, buffer)).freeze
    end

    def window_state_snapshot(window, buffer)
      {
        modified: buffer.modified?,
        readonly: buffer.readonly,
        name: snapshot_buffer_name(buffer),
        top_line: window.top_line,
        left_column: window.left_column,
        active: window.equal?(current_window)
      }.merge(window_position_snapshot(window))
    end

    def window_position_snapshot(window)
      { point: window.point.dup.freeze, mark: window.mark&.dup&.freeze, highlight: window.highlight }
    end

    def snapshot_buffer_name(buffer)
      (buffer.filename || buffer.name || "*scratch*").to_s.dup.freeze
    end
  end
end
