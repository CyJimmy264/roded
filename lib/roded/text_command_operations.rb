module Roded
  # Implements small, reversible text commands used by the shared keymap.
  module TextCommandOperations
    INDENT = "  ".freeze
    DATE_TIME_FORMAT = "%d/%m/%Y %H:%M:%S".freeze
    TIME_FORMAT = "%H:%M:%S".freeze

    def select_current_line
      return unless current_buffer && current_window

      select_line(current_window.point.fetch(:row))
    end

    def insert_current_date_time
      insert_text_command(Time.now.strftime(DATE_TIME_FORMAT))
    end

    def insert_current_time
      insert_text_command(Time.now.strftime(TIME_FORMAT))
    end

    def insert_binding_irb
      return unless editable_text_target?

      insert_binding_on_next_line(current_window.point.fetch(:row))
    end

    private

    def insert_text_command(text)
      return unless editable_text_target?

      current_buffer.insert_text(text)
      current_window.point = current_buffer.cursor_pos
      broadcast_command(Command.new(:render, {}))
    end

    def select_line(row)
      current_window.mark = { row:, col: 0 }
      current_window.point = { row:, col: current_buffer.lines.fetch(row).length }
      current_buffer.cursor_pos = current_window.point
      broadcast_command(Command.new(:render, {}))
    end

    def insert_binding_on_next_line(row)
      line = current_buffer.lines.fetch(row)
      indentation = line[/\A[ \t]*/]
      current_buffer.cursor_pos = { row:, col: line.length }
      current_buffer.insert_text("\n#{indentation}binding.irb")
      current_window.point = current_buffer.cursor_pos
      broadcast_command(Command.new(:render, {}))
    end

    def editable_text_target?
      current_buffer && current_window && !current_buffer.readonly
    end
  end
end
