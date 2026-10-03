module Roded
  module Frontends
    # Renders one editor view and routes its key events to the core.
    class QtEditorPane
      # TODO(qt): HACK — qt 0.1.9 omits QTextCursor::MoveOperation enum names.
      # Workaround: use Qt's public integer values to place the read-only view cursor.
      # Extend the binding to expose this enum, then replace these values with named constants.
      MOVE_START = 1
      MOVE_DOWN = 12
      MOVE_RIGHT = 19

      attr_reader :container, :editor

      def initialize(parent)
        @container = QWidget.new(parent)
        layout = QVBoxLayout.new(@container)
        @editor = QTextEdit.new(@container)
        @editor.set_read_only(true)
        @modeline = QLabel.new(@container)
        layout.add_widget(@editor)
        layout.add_widget(@modeline)
        @subscribed = false
      end

      def bind(window_id, callback)
        @window_id = window_id
        @key_callback = callback
        subscribe_keys
      end

      def render(snapshot)
        text = snapshot.fetch(:text).gsub("\r\n", "\n")
        @editor.set_html(rendered_html(text, snapshot[:mark], snapshot[:point]))
        place_cursor(snapshot.fetch(:row, snapshot.dig(:point, :row)),
                     snapshot.fetch(:col, snapshot.dig(:point, :col)))
        @modeline.set_text(snapshot[:modeline] || modeline_for(snapshot))
      end

      private

      def subscribe_keys
        return if @subscribed || !@key_callback

        @editor.on(:key_press) do |payload|
          @key_callback.call(payload.merge(window_id: @window_id))
        end
        @subscribed = true
      end

      def modeline_for(snapshot)
        point = snapshot.fetch(:point)
        active = snapshot[:active] ? "--" : "  "
        "#{active} Roded -- #{snapshot.fetch(:name)}  #{point[:row] + 1}:#{point[:col] + 1}"
      end

      def rendered_html(text, mark, point)
        lines = text.split("\n", -1)
        ranges = mark && point && mark != point ? ordered_range(mark, point) : nil
        content = lines.each_with_index.map do |line, row|
          render_line(line, row, ranges)
        end.join("<br>")
        "<pre style=\"white-space: pre-wrap; font-family: monospace; margin: 0;\">#{content}</pre>"
      end

      def ordered_range(mark, point)
        [mark, point].sort_by { |position| [position[:row], position[:col]] }
      end

      def render_line(line, row, range)
        columns = selected_columns(line, row, range)
        return escape_html(line) unless columns

        first, last = columns
        before, selected, after = [line[0...first], line[first...last], line[last..]].map do |part|
          escape_html(part.to_s)
        end
        "#{before}<span style=\"background-color: #3e4451;\">#{selected}</span>#{after}"
      end

      def selected_columns(line, row, range)
        return unless range && row.between?(range.first[:row], range.last[:row])

        first = row == range.first[:row] ? range.first[:col] : 0
        last = row == range.last[:row] ? range.last[:col] : line.length
        [first, last]
      end

      def escape_html(text)
        text.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
      end

      def place_cursor(row, col)
        return unless row && col

        @editor.move_cursor(MOVE_START)
        row.times { @editor.move_cursor(MOVE_DOWN) }
        col.times { @editor.move_cursor(MOVE_RIGHT) }
        @editor.ensure_cursor_visible
      end
    end
  end
end
