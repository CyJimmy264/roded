require_relative "scenario"

# The catalog deliberately keeps scenario preparation/actions/assertions together.
# rubocop:disable Metrics/ModuleLength, Metrics/AbcSize, Metrics/MethodLength

module Roded
  module Benchmarking
    # Extensible catalog of one user operation per timed invocation.
    module Scenarios
      def self.all
        cursor + scrolling + editing + history + buffers + windows + diagnostics
      end

      def self.cursor
        movements = {
          "cursor.line_down" => [:move_down, 1, 0], "cursor.line_up" => [:move_up, -1, 0],
          "cursor.char_right" => [:move_right, 0, 1], "cursor.char_left" => [:move_left, 0, -1],
          "cursor.page_down" => [:page_down, 38, 0], "cursor.page_up" => [:page_up, -38, 0]
        }
        movements.map do |name, (event, row_delta, col_delta)|
          command(name, event) do |work|
            work.window.point == { row: work.middle + row_delta, col: 12 + col_delta }
          end
        end + cursor_boundaries + words
      end

      def self.cursor_boundaries
        [
          command("cursor.line_start", :line_start) { |work| work.window.point == { row: work.middle, col: 0 } },
          command("cursor.line_end", :line_end) do |work|
            work.window.point == { row: work.middle, col: work.buffer.lines[work.middle].length }
          end,
          command("cursor.document_start", :document_start) { |work| work.window.point == { row: 0, col: 0 } },
          command("cursor.document_end", :document_end) do |work|
            work.window.point == { row: work.fixture.line_count - 1, col: work.buffer.lines.last.length }
          end
        ]
      end

      def self.words
        %i[forward backward].map do |direction|
          command("cursor.word_#{direction}", :"move_word_#{direction}") do |work|
            point = work.window.point
            point[:row] == work.middle && (direction == :forward ? point[:col] > 12 : point[:col] < 12)
          end
        end
      end

      def self.scrolling
        vertical = { line_down: 1, line_up: -1, page_down: 38, page_up: -38 }.map do |name, amount|
          command("scroll.#{name}", :"scroll_#{name}") do |work|
            work.window.top_line == work.middle - 10 + amount && work.window.point[:row] == work.middle + amount
          end
        end
        vertical + [Scenario.new(
          "scroll.horizontal", ->(work) { work.position(col: 200, left: 160) },
          lambda { |work|
            work.dispatch(:horizontal_scroll, left_column: 180)
            work.dispatch(:render)
          }, ->(work) { work.window.left_column == 180 && work.window.point[:col] == 200 }
        )]
      end

      def self.editing
        [
          command("edit.insert_char", :insert_char, char: "x") { |work| work.buffer.lines[work.middle][12] == "x" },
          command("edit.backspace", :backspace) { |work| work.window.point[:col] == 11 && work.buffer.modified? },
          command("edit.delete_char", :delete) do |work|
            work.buffer.lines[work.middle].length == work.fixture.text.split("\n")[work.middle].length - 1
          end,
          command("edit.newline", :enter) { |work| work.buffer.lines.length == work.fixture.line_count + 1 },
          Scenario.new("edit.paste_block", noop, ->(work) { work.dispatch(:paste, text: work.fixture.block) },
                       ->(work) { work.buffer.lines.length == work.fixture.line_count + 99 }),
          Scenario.new("edit.delete_block", lambda { |work|
            work.window.mark = { row: work.middle, col: 0 }
            work.window.point = { row: work.middle + 100, col: 0 }
          }, ->(work) { work.dispatch(:kill_region) },
                       ->(work) { work.buffer.lines.length == work.fixture.line_count - 100 })
        ]
      end

      def self.history
        [
          Scenario.new("edit.undo", ->(work) { work.dispatch(:insert_char, char: "x") },
                       ->(work) { work.dispatch(:undo) }, ->(work) { work.buffer.to_s == work.fixture.text }),
          Scenario.new("edit.redo", lambda { |work|
            work.dispatch(:insert_char, char: "x")
            work.dispatch(:undo)
          }, ->(work) { work.dispatch(:redo) }, ->(work) { work.buffer.lines[work.middle][12] == "x" })
        ]
      end

      def self.buffers
        [
          command("buffer.next", :next_buffer) { |work| work.buffer.equal?(work.documents[1]) },
          command("buffer.previous", :previous_buffer) { |work| work.buffer.equal?(work.documents.last) }
        ]
      end

      def self.windows
        %i[horizontal vertical].map do |direction|
          command("window.split_#{direction}", :"split_#{direction}") do |work|
            work.application.windows.length == work.base_windows.length + 1
          end
        end + [
          Scenario.new("window.delete", ->(work) { work.dispatch(:split_vertical) },
                       ->(work) { work.dispatch(:delete_window) },
                       ->(work) { work.application.windows.length == work.base_windows.length }),
          Scenario.new("window.other", lambda { |work|
            work.dispatch(:split_vertical)
            work.application.current_window = work.application.windows.last
          },
                       ->(work) { work.dispatch(:other_window) },
                       ->(work) { work.window.equal?(work.base_windows.first) }),
          Scenario.new("window.delete_others", ->(work) { 3.times { work.dispatch(:split_vertical) } },
                       ->(work) { work.dispatch(:delete_other_windows) },
                       ->(work) { work.application.windows.length == 1 })
        ]
      end

      def self.diagnostics
        [command("render.full", :render) { |work| work.buffer.to_s == work.fixture.text },
         command("input.key_down", :key, key: "C-n") { |work| work.window.point[:row] == work.middle + 1 }]
      end

      def self.command(name, event, **payload, &verify)
        Scenario.new(name, noop, ->(work) { work.dispatch(event, payload) }, verify)
      end

      def self.noop = ->(_work) {}
    end
  end
end
# rubocop:enable Metrics/ModuleLength, Metrics/AbcSize, Metrics/MethodLength
