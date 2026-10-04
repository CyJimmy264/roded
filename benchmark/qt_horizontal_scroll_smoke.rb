#!/usr/bin/env ruby

require_relative "../lib/roded"
require_relative "roded/cli"

module Roded
  module Benchmarking
    # Compares incremental X11 painting of unchanged rows with a fresh viewport paint.
    class QtHorizontalScrollSmoke
      def run
        Isolation.run(xvfb: true) do
          build_workspace
          Dir.mktmpdir("roded-horizontal-frames") do |directory|
            @directory = directory
            %i[move_right move_word_forward move_left move_word_backward].each { |operation| check(operation) }
          end
        ensure
          @work&.close
        end
      end

      private

      def build_workspace
        fixture = Fixture.new(line_count: 1500, profile: "plain", line_length: 2500)
        @work = Workspace.new(layer: "qt", fixture:, buffer_count: 2, window_count: 1)
        @view = @work.frontend.frontend.view
        @view.window.resize(420, 240)
        @work.frontend.finish
      end

      def check(operation)
        prepare(operation)
        check_movement(operation)
        @view.editor.viewport.update
        @work.frontend.finish
        capture("complete")
        raise "#{operation}: adjacent rows retained stale pixels" unless same_frame?("incremental", "complete")

        puts "Qt horizontal visible frame passed: #{operation} (1500 rows, 2500+ characters per row)"
      end

      def check_movement(operation)
        capture("before")
        previous = @view.editor.horizontal_scroll_bar.value
        @work.dispatch(operation)
        @work.frontend.finish
        raise "#{operation}: viewport did not scroll" if @view.editor.horizontal_scroll_bar.value == previous

        capture("incremental")
        raise "#{operation}: adjacent rows did not move" if same_frame?("before", "incremental")
      end

      def prepare(operation)
        @work.reset
        @work.render
        position_for(operation)
        @work.render
        @view.editor.viewport.update
        @work.frontend.finish
      end

      def position_for(operation)
        if %i[move_right move_word_forward].include?(operation)
          @work.position(col: right_edge_column, origin: @work.middle - 1)
        else
          @work.position(col: 100, left: 100, origin: @work.middle - 1)
        end
      end

      def right_edge_column
        editor = @view.editor
        line = @work.buffer.lines[@work.middle]
        available = Frontends::QtCursorMapper.available_cursor_width(editor, line, 0)
        (0...line.length).bsearch do |column|
          Frontends::QtCursorMapper.line_horizontal_offset(editor, line, column) >= available
        end - 1
      end

      def capture(name)
        system("import", "-window", "root", "-crop", adjacent_rows_crop, frame_path(name), exception: true)
      end

      def adjacent_rows_crop
        editor = @view.editor
        origin = viewport_origin
        caret = editor.cursor_rect
        y = (origin.y + caret.y + caret.height + 2).round
        "#{editor.viewport.width}x#{caret.height * 2}+#{origin.x}+#{y}"
      end

      def viewport_origin = @view.editor.viewport.map_to_global(::Qt::QPointF.new).to_point

      def same_frame?(first, second)
        system("compare", "-metric", "AE", frame_path(first), frame_path(second), "null:", err: File::NULL)
      end

      def frame_path(name) = File.join(@directory, "#{name}.png")
    end
  end
end

Roded::Benchmarking::QtHorizontalScrollSmoke.new.run
