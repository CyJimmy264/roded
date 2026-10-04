#!/usr/bin/env ruby

require_relative "../lib/roded"
require_relative "roded/cli"
require_relative "qt_frame_capture"

def assert_visible_frame(work)
  view = work.frontend.frontend.view
  id = work.window.object_id
  pane = view.instance_variable_get(:@panes).fetch(id)
  assert_editor_geometry(view, pane)
  assert_caret_geometry(view.editor)
  assert_presentation(work, pane)
end

def assert_presentation(work, pane)
  modeline = pane.instance_variable_get(:@modeline)
  editor = pane.editor
  point = work.window.point
  raise "modeline failed to update" unless modeline.text.include?("#{point[:row] + 1}:#{point[:col] + 1}")
  raise "caret failed to paint" unless editor.to_html.include?("background-color:#61afef")

  assert_current_line_background(editor, point[:row])
end

def assert_current_line_background(editor, expected_row)
  paragraphs = editor.to_html.scan(/<(?:p|pre) [^>]*>/)
  active = paragraphs.each_index.select { |row| paragraphs[row].include?("background-color:#343a46") }
  raise "current-line background failed to follow the caret: #{active.inspect}" unless active == [expected_row]
end

def assert_editor_geometry(view, pane)
  raise "editor frame is hidden" unless [view.window, pane.container, view.editor].all?(&:is_visible)
  raise "editor geometry is empty" unless view.editor.width > 100 && view.editor.height > 100
end

def assert_caret_geometry(editor)
  rectangle = editor.cursor_rect
  return if caret_geometry_visible?(editor, rectangle)

  raise "caret is outside the viewport: x=#{rectangle.x}, y=#{rectangle.y}, height=#{editor.viewport.height}, " \
        "scroll=#{editor.vertical_scroll_bar.value}, step=#{editor.vertical_scroll_bar.single_step}"
end

def caret_geometry_visible?(editor, rectangle)
  width = editor.font_metrics.horizontal_advance(" ", 1)
  horizontal = rectangle.x >= 0 && rectangle.x + width <= editor.viewport.width
  horizontal && rectangle.y >= 0 && rectangle.y < editor.viewport.height
end

def capture_frame(scenario, editor)
  directory = ENV.fetch("RODED_BENCHMARK_SCREENSHOT_DIR", nil)
  return unless directory

  Roded::Benchmarking::QtFrameCapture.new(directory).capture(scenario.name, editor)
end

def visible_scenarios(profile)
  selected = %w[cursor.char_left cursor.char_right cursor.line_down scroll.page_down scroll.horizontal
                edit.backspace edit.insert_char edit.newline render.full
                edit.paste_block edit.delete_block buffer.next
                window.split_vertical window.delete]
  scenarios = Roded::Benchmarking::Scenarios.all.select { |scenario| selected.include?(scenario.name) }
  scenarios << right_edge_scenario
  scenarios << string_context_scenario if profile == "ruby"
  scenarios
end

def right_edge_scenario
  Roded::Benchmarking::Scenario.new(
    "cursor.right_edge", method(:prepare_right_edge), ->(work) { work.dispatch(:move_right) },
    ->(work) { work.frontend.frontend.view.editor.horizontal_scroll_bar.value.positive? }
  )
end

def prepare_right_edge(work)
  editor = work.frontend.frontend.view.editor
  line = work.buffer.lines[work.middle]
  work.position(col: right_edge_column(editor, line) - 1)
end

def right_edge_column(editor, line)
  threshold = editor.viewport.width - editor.document.property("documentMargin").to_f
  (0..line.length).bsearch do |candidate|
    Roded::Frontends::QtCursorMapper.line_horizontal_offset(editor, line, candidate) >= threshold
  end
end

def string_context_scenario
  Roded::Benchmarking::Scenario.new(
    "edit.string_context", method(:prepare_string_context),
    ->(work) { work.dispatch(:delete) },
    ->(work) { work.buffer.lines[work.middle].count('"') == 1 }
  )
end

def prepare_string_context(work)
  column = work.buffer.lines[work.middle].index('"')
  work.position(row: work.middle, col: column)
end

def assert_syntax_snapshot(work)
  snapshot = work.application.editor_snapshot[:windows].find { |item| item[:id] == work.window.object_id }
  expected = Roded::SyntaxHighlighter.new.spans(:ruby, work.buffer.lines)
  raise "deferred syntax differs from the complete lexer" unless snapshot[:tokens] == expected

  assert_ruby_number_color(work)
end

def assert_ruby_number_color(work)
  return if work.frontend.frontend.view.editor.to_html.include?("color:#d19a66")

  raise "Ruby number colors did not reach the visible editor"
end

Roded::Benchmarking::Isolation.run(xvfb: true) do
  profile = ENV.fetch("RODED_BENCHMARK_PROFILE", "plain")
  fixture = Roded::Benchmarking::Fixture.new(line_count: 1500, profile:)
  work = Roded::Benchmarking::Workspace.new(layer: "qt", fixture:, buffer_count: 4, window_count: 1)
  visible_scenarios(profile).each do |scenario|
    work.reset
    scenario.prepare.call(work)
    work.render
    scenario.action.call(work)
    work.frontend.finish
    raise "operation failed: #{scenario.name}" unless scenario.verify.call(work)

    assert_visible_frame(work)
    work.settle_highlighting
    assert_visible_frame(work)
    assert_syntax_snapshot(work) if profile == "ruby"
    editor = work.frontend.frontend.view.editor
    capture_frame(scenario, editor)
    if scenario.name == "scroll.page_down"
      raise "vertical viewport did not scroll" unless editor.vertical_scroll_bar.value.positive?
    elsif scenario.name == "scroll.horizontal"
      raise "horizontal viewport did not scroll" unless editor.horizontal_scroll_bar.value.positive?
    end
    puts "Qt benchmark visible frame passed: #{scenario.name}"
  end
ensure
  work&.close
end
