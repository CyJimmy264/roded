module Roded
  # Coordinates candidate lists and their actions for the shared editor.
  module PickerOperations
    def choose_yank_pop(text)
      return if text.to_s.empty?

      previous = @last_yank&.fetch(:buffer).equal?(current_buffer) ? @last_yank : nil
      replace_yank(text, previous)
    end

    def select_picker_line(candidate)
      row = picker_line_row(candidate)
      return display_message("No matching line.") unless valid_picker_row?(row)

      query = @picker_query.to_s
      column = matching_column(current_buffer.lines.fetch(row), query)
      highlight = { start: { row:, col: column }, finish: { row:, col: column + query.length } }
      move_to_position(row, column, highlight:)
    end

    def move_picker(amount)
      return unless @picker

      @picker.move(amount)
      render_picker
    end

    def move_picker_history(amount)
      return unless @picker

      @minibuffer.replace_text(@picker.move_history(amount))
      render_minibuffer
      render_picker
    end

    def refresh_picker
      return unless @picker

      @picker.update_query(@minibuffer.text)
      render_picker
    end

    def render_picker
      return unless @picker

      payload = @picker.snapshot.merge(prompt: @minibuffer.prompt).freeze
      broadcast_command(Command.new(:picker_render, payload))
    end

    def selected_picker_value
      @picker&.selected
    end

    private

    def replace_yank(text, previous)
      start = previous ? previous.fetch(:start) : current_window.point.dup
      current_buffer.with_undo_group do
        current_buffer.delete_region(previous.fetch(:start), previous.fetch(:finish)) if previous
        current_buffer.insert_text(text)
      end
      remember_yank(text, start)
    end

    def remember_yank(text, start)
      index = kill_ring.items.index(text) || 0
      @last_yank = { buffer: current_buffer, start:, finish: current_buffer.cursor_pos, index: index }
      current_window.mark = nil
      broadcast_command(Command.new(:render, {}))
    end

    def matching_column(line, query)
      return 0 if query.empty?

      line.downcase.index(query.downcase) || 0
    end

    def picker_line_row(candidate)
      candidate.to_s.strip[/\A(\d+):/, 1].to_i - 1
    end

    def valid_picker_row?(row)
      row.between?(0, current_buffer.lines.length - 1)
    end

    def path_picker?(kind)
      %i[open save save_as].include?(kind)
    end

    def continue_path_picker(query, kind)
      prompt = @minibuffer.prompt
      @minibuffer.start(prompt)
      query.each_char { |character| @minibuffer.insert_char(character) }
      @minibuffer_kind = kind
      @picker = picker_for(kind)
      @picker.update_query(query)
      @focus = :minibuffer
      broadcast_focus
      render_minibuffer
      render_picker
    end
  end
end
