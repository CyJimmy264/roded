module Roded
  module Benchmarking
    # Independent expected cursor/text transitions for real-key workloads.
    class LatencyWorkload
      NAMES = %w[char line word page edit typing].freeze
      ACTIONS = {
        "char" => [["cursor.char_right", "Control_L+f"], ["cursor.char_left", "Control_L+b"]],
        "line" => [["cursor.line_down", "Control_L+n"], ["cursor.line_up", "Control_L+p"]],
        "word" => [["cursor.word_forward", "Alt_L+f"], ["cursor.word_backward", "Alt_L+b"]],
        "page" => [["cursor.page_down", "Control_L+v"], ["cursor.page_up", "Alt_L+v"]],
        "edit" => [["edit.insert_char", "x"], ["edit.backspace", "BackSpace"]],
        "typing" => [["edit.consecutive_typing", "x"]]
      }.freeze
      LOCAL_MOVEMENTS = {
        "cursor.char_right" => ["col", 1], "cursor.char_left" => ["col", -1],
        "cursor.line_down" => ["row", 1], "cursor.line_up" => ["row", -1]
      }.freeze

      def initialize(name, fixture, page_size:)
        @actions = ACTIONS.fetch(name)
        @lines = fixture.text.split("\n")
        @point = { "row" => fixture.line_count / 2, "col" => 4 }
        @page_size = page_size
        @top_line = @point.fetch("row") - 10
      end

      def action(index) = @actions[index % @actions.length]

      def verify(record, scenario)
        advance(scenario)
        raise "unexpected point: #{record.fetch("point")}, expected #{@point}" unless record.fetch("point") == @point
        raise "unexpected viewport origin" unless record.fetch("top_line") == @top_line
        return if record.fetch("line") == @lines.fetch(@point.fetch("row"))

        raise "key changed the wrong text"
      end

      private

      def advance(scenario)
        case scenario
        when "cursor.word_forward" then @point["col"] = @lines.fetch(@point.fetch("row"))[/\A[[:alnum:]_]+/].length
        when "cursor.word_backward" then @point["col"] = 0
        when "cursor.page_down" then move_page(@page_size)
        when "cursor.page_up" then move_page(-@page_size)
        else advance_local_or_edit(scenario)
        end
      end

      def advance_local_or_edit(scenario)
        movement = LOCAL_MOVEMENTS[scenario]
        return edit(scenario) unless movement

        axis, amount = movement
        @point[axis] += amount
      end

      def move_page(amount)
        @point["row"] += amount
        row = @point.fetch("row")
        @top_line = row if row < @top_line
        @top_line = row - @page_size + 1 if row >= @top_line + @page_size
      end

      def edit(scenario)
        row, col = @point.values_at("row", "col")
        text = @lines.fetch(row)
        if scenario == "edit.backspace"
          @lines[row] = text[0...(col - 1)] + text[col..]
          @point["col"] -= 1
        else
          @lines[row] = "#{text[0...col]}x#{text[col..]}"
          @point["col"] += 1
        end
      end
    end
  end
end
