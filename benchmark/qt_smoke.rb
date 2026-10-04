#!/usr/bin/env ruby

require_relative "../lib/roded"
require_relative "roded/cli"

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
  return if rectangle.y >= 0 && rectangle.y < editor.viewport.height

  raise "caret is outside the viewport: y=#{rectangle.y}, height=#{editor.viewport.height}, " \
        "scroll=#{editor.vertical_scroll_bar.value}, step=#{editor.vertical_scroll_bar.single_step}"
end

def capture_frame(scenario)
  directory = ENV.fetch("RODED_BENCHMARK_SCREENSHOT_DIR", nil)
  return unless directory

  FileUtils.mkdir_p(directory)
  path = File.join(directory, "#{scenario.name.tr(".", "_")}.png")
  raise "could not capture visible Xvfb frame" unless system("import", "-window", "root", path)
end

Roded::Benchmarking::Isolation.run(xvfb: true) do
  profile = ENV.fetch("RODED_BENCHMARK_PROFILE", "plain")
  fixture = Roded::Benchmarking::Fixture.new(line_count: 1500, profile:)
  work = Roded::Benchmarking::Workspace.new(layer: "qt", fixture:, buffer_count: 4, window_count: 1)
  selected = %w[cursor.line_down scroll.page_down scroll.horizontal edit.insert_char edit.newline
                edit.paste_block edit.delete_block buffer.next
                window.split_vertical window.delete]
  Roded::Benchmarking::Scenarios.all.select { |scenario| selected.include?(scenario.name) }.each do |scenario|
    work.reset
    scenario.prepare.call(work)
    work.render
    scenario.action.call(work)
    work.frontend.finish
    raise "operation failed: #{scenario.name}" unless scenario.verify.call(work)

    assert_visible_frame(work)
    capture_frame(scenario)
    editor = work.frontend.frontend.view.editor
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
