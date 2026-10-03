module Roded
  # Converts tabs and spaces in selected lines while preserving view positions.
  module TabConversionOperations
    TAB_WIDTH = 2

    def tabify
      transform_text_rows(:spaces_to_tabs)
    end

    def untabify
      transform_text_rows(:tabs_to_spaces)
    end

    private

    def transform_text_rows(mode)
      return unless editable_text_target?

      changed = changed_text_rows(mode)
      return if changed.empty?

      apply_text_transformation(changed, mode)
    end

    def apply_text_transformation(changed, mode)
      positions = windows_for_current_buffer.map do |window|
        { window:, point: window.point, mark: window.mark }
      end
      current_buffer.with_undo_group { replace_changed_rows(changed) }
      restore_transformed_positions(positions, changed, mode)
      current_buffer.cursor_pos = current_window.point
      publish_ui_update(UIUpdate.new(:render, {}))
    end

    def changed_text_rows(mode)
      rows_for_text_command.each_with_object({}) do |row, changed|
        original = current_buffer.lines.fetch(row)
        replacement = transform_tabs(original, mode)
        changed[row] = [original, replacement] if original != replacement
      end
    end

    def replace_changed_rows(changed)
      changed.keys.reverse_each do |row|
        original, replacement = changed.fetch(row)
        replace_line(row, original, replacement)
      end
    end

    def transform_tabs(text, mode)
      return text.gsub("\t", " " * TAB_WIDTH) if mode == :tabs_to_spaces

      text.gsub(/ {2,}/) do |spaces|
        ("\t" * (spaces.length / TAB_WIDTH)) + (spaces.length.odd? ? " " : "")
      end
    end

    def rows_for_text_command
      mark = current_window.mark
      return (0...current_buffer.lines.length).to_a unless mark

      point_row = current_window.point.fetch(:row)
      ([mark.fetch(:row), point_row].min..[mark.fetch(:row), point_row].max).to_a
    end

    def windows_for_current_buffer
      windows.select { |window| window.buffer.equal?(current_buffer) }
    end

    def replace_line(row, original, replacement)
      start = { row:, col: 0 }
      finish = { row:, col: original.length }
      current_buffer.cursor_pos = start
      current_buffer.delete_region(start, finish) unless original.empty?
      current_buffer.insert_text(replacement) unless replacement.empty?
    end

    def restore_transformed_positions(positions, changed, mode)
      positions.each do |saved|
        saved[:window].point = map_tab_position(saved[:point], changed, mode)
        mark = saved[:mark] && map_tab_position(saved[:mark], changed, mode)
        saved[:window].mark = mark
      end
    end

    def map_tab_position(position, changed, mode)
      row = position.fetch(:row)
      return position unless changed.key?(row)

      prefix = changed.fetch(row).first[0...position.fetch(:col)]
      { row:, col: transform_tabs(prefix, mode).length }
    end
  end
end
