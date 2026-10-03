require_relative "cursor_mapper"

module Roded
  module Frontends
    # Renders one editor view and routes its key events to the core.
    class QtEditorPane
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
        @editor.set_html(rendered_html(text, snapshot[:mark], snapshot[:point],
                                      snapshot[:tokens], snapshot[:highlight]))
        QtCursorMapper.place(@editor, snapshot, text)
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
        modified = snapshot[:modified] ? " *" : ""
        readonly = snapshot[:readonly] ? " RO" : ""
        mode = snapshot[:mode] || :plain
        "#{active} #{snapshot.fetch(:name)}#{modified}#{readonly}  #{mode}  #{point[:row] + 1}:#{point[:col] + 1}"
      end

      def rendered_html(text, mark, point, tokens, highlight)
        lines = text.split("\n", -1)
        ranges = mark && point && mark != point ? ordered_range(mark, point) : nil
        content = lines.each_with_index.map do |line, row|
          render_line(line, row, ranges, tokens&.[](row), highlight)
        end.join("<br>")
        "<pre style=\"white-space: pre-wrap; font-family: monospace; margin: 0;\">#{content}</pre>"
      end

      def ordered_range(mark, point)
        [mark, point].sort_by { |position| [position[:row], position[:col]] }
      end

      def render_line(line, row, range, tokens, highlight)
        boundaries = line_boundaries(line, row, range, tokens, highlight)
        boundaries.each_cons(2).map do |first, last|
          render_segment(line, row, first, last, range, tokens, highlight)
        end.join
      end

      def selected_columns(line, row, range)
        return unless range && row.between?(range.first[:row], range.last[:row])

        first = row == range.first[:row] ? range.first[:col] : 0
        last = row == range.last[:row] ? range.last[:col] : line.length
        [first, last]
      end

      def line_boundaries(line, row, range, tokens, highlight)
        columns = [0, line.length]
        tokens.to_a.each { |token| columns.concat([token[:start], token[:finish]]) }
        columns.concat(selected_columns(line, row, range)) if selected_columns(line, row, range)
        columns.concat(highlight_columns(line, row, highlight)) if highlight_columns(line, row, highlight)
        columns.map { |column| column.clamp(0, line.length) }.uniq.sort
      end

      def render_segment(line, row, first, last, range, tokens, highlight)
        value = escape_html(line[first...last].to_s)
        styles = []
        token = tokens.to_a.find { |span| span[:start] <= first && span[:finish] >= last }
        styles << "color: #{SyntaxHighlighter::COLORS.fetch(token[:category])};" if token
        selected = selected_columns(line, row, range)
        matched = highlight_columns(line, row, highlight)
        if matched && first >= matched.first && last <= matched.last
          styles << "color: #282c34; background-color: #e5c07b;"
        elsif selected && first >= selected.first && last <= selected.last
          styles << "background-color: #3e4451;"
        end
        styles.empty? ? value : "<span style=\"#{styles.join}\">#{value}</span>"
      end

      def highlight_columns(line, row, highlight)
        return unless highlight && row.between?(highlight[:start][:row], highlight[:finish][:row])

        first = row == highlight[:start][:row] ? highlight[:start][:col] : 0
        last = row == highlight[:finish][:row] ? highlight[:finish][:col] : line.length
        [first, last.clamp(0, line.length)]
      end

      def escape_html(text)
        text.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
      end

    end
  end
end
