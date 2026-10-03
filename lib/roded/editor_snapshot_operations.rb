module Roded
  # Produces immutable snapshots and propagates edits to other views.
  module EditorSnapshotOperations
    def editor_snapshot
      {
        tree: @window_layout.snapshot_tree,
        active_window_id: @current_window&.object_id,
        windows: windows.map { |window| window_snapshot(window) }.freeze
      }.freeze
    end

    def buffer_edited(buffer, position_change)
      windows.each do |window|
        window.transform_positions(position_change) if window.buffer.equal?(buffer)
      end
    end

    private

    def activate_window(window)
      @current_window = window
      @current_buffer = window.buffer
      @current_buffer.cursor_pos = window.point
      render_active_window
    end

    def render_active_window
      @frontends.each { |frontend| frontend.render(current_buffer) }
      broadcast_command(Command.new(:render, {}))
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
        point: window.point.dup.freeze,
        mark: window.mark&.dup&.freeze,
        highlight: window.highlight,
        name: (buffer.filename || buffer.name || "*scratch*").to_s.dup.freeze,
        top_line: window.top_line,
        left_column: window.left_column,
        active: window.equal?(@current_window)
      }
    end
  end
end
