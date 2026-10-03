module Roded
  module Frontends
    # Formats and paints the status row for each curses editor window.
    module CursesModelineOperations
      private

      def draw_modeline(item, row, left, width)
        writer = proc { write_at(row, left, modeline_text(item), width) }
        item[:active] ? @screen.attron(::Curses::A_REVERSE, &writer) : writer.call
      end

      def modeline_text(item)
        active_marker = item[:active] ? "*" : "-"
        modified = item[:modified] ? "*" : ""
        readonly = item[:readonly] ? " RO" : ""
        mode_name = item[:mode] || :plain
        point = item[:point]
        "#{active_marker} #{item[:name]}#{modified}#{readonly}  #{mode_name}  #{point[:row] + 1}:#{point[:col] + 1}"
      end
    end
  end
end
