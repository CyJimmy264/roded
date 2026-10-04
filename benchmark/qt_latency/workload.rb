module Roded
  module Benchmarking
    # Independent expected cursor/text transitions for real-key workloads.
    class LatencyWorkload
      NAMES = %w[char line edit typing].freeze
      ACTIONS = {
        "char" => [["cursor.char_right", "Control_L+f"], ["cursor.char_left", "Control_L+b"]],
        "line" => [["cursor.line_down", "Control_L+n"], ["cursor.line_up", "Control_L+p"]],
        "edit" => [["edit.insert_char", "x"], ["edit.backspace", "BackSpace"]],
        "typing" => [["edit.consecutive_typing", "x"]]
      }.freeze

      def initialize(name, fixture)
        @actions = ACTIONS.fetch(name)
        @lines = fixture.text.split("\n")
        @point = { "row" => fixture.line_count / 2, "col" => 4 }
      end

      def action(index) = @actions[index % @actions.length]

      def verify(record, scenario)
        advance(scenario)
        raise "unexpected point: #{record.fetch("point")}, expected #{@point}" unless record.fetch("point") == @point
        return if record.fetch("line") == @lines.fetch(@point.fetch("row"))

        raise "key changed the wrong text"
      end

      private

      def advance(scenario)
        case scenario
        when "cursor.char_right" then @point["col"] += 1
        when "cursor.char_left" then @point["col"] -= 1
        when "cursor.line_down" then @point["row"] += 1
        when "cursor.line_up" then @point["row"] -= 1
        else edit(scenario)
        end
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
