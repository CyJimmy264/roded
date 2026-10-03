require "spec_helper"
require "roded/frontends/curses"

module CursesPickerRenderSpecSupport
  class Screen
    attr_reader :writes, :clear_rows, :refresh_count

    def initialize
      @writes = []
      @clear_rows = []
      @refresh_count = 0
      @position = {}
    end

    def maxy = 12
    def maxx = 40
    def clear = nil

    def refresh
      @refresh_count += 1
    end

    def setpos(row, column)
      @position = { row:, column: }
    end

    def clrtoeol
      @clear_rows << @position[:row]
    end

    def addstr(text)
      @writes << [@position[:row], text]
    end
  end

  class Frontend < Roded::Frontends::Curses
    attr_reader :modeline_rows

    def initialize_for_test(screen)
      @screen = screen
      @color_pairs = {}
      @minibuffer_state = nil
      @picker_state = nil
      @modeline_rows = []
      @buffer_rows = []
    end

    private

    def draw_buffer_line(context)
      @buffer_rows << context.screen_row
    end

    def draw_modeline(_item, row, *_arguments)
      @modeline_rows << row
    end
  end

  def self.build_frontend
    screen = Screen.new
    frontend = Frontend.allocate
    frontend.initialize_for_test(screen)
    { frontend:, screen:, writes: screen.writes, clear_rows: screen.clear_rows, modeline_rows: frontend.modeline_rows }
  end

  def self.editor_snapshot
    item = {
      id: 1, lines: (1..20).map { |number| "Line #{number}" }, tokens: Array.new(20) { [] },
      point: { row: 0, col: 0 }, mark: nil, highlight: nil, name: "scratch", mode: :plain,
      modified: false, readonly: false, active: true, top_line: 0, left_column: 0
    }
    { tree: { window_id: 1 }, active_window_id: 1, windows: [item] }
  end

  def self.picker_payload(selected_index:, candidates: %w[alpha.rb beta.rb gamma.rb])
    { candidates:, selected_index:, prompt: "Project file: " }
  end

  def self.picker_writes(writes)
    writes.select { |_row, text| text.match?(/\A(?:> |  ).*\.rb\z/) }
          .map { |row, text| [row, text] }
  end
end

RSpec.describe Roded::Frontends::Curses, "picker candidate rendering" do
  it "places candidates under the modeline and refreshes selection changes" do
    context = CursesPickerRenderSpecSupport.build_frontend
    frontend = context.fetch(:frontend)
    frontend.send(:render_layout, CursesPickerRenderSpecSupport.editor_snapshot)
    frontend.send(:show_picker, CursesPickerRenderSpecSupport.picker_payload(selected_index: 0))

    expect(context.fetch(:modeline_rows).last).to eq(7)
    expected_rows = [[8, "> alpha.rb"], [9, "  beta.rb"], [10, "  gamma.rb"]]
    expect(CursesPickerRenderSpecSupport.picker_writes(context.fetch(:writes))).to eq(expected_rows)

    context.fetch(:writes).clear
    frontend.send(:show_picker, CursesPickerRenderSpecSupport.picker_payload(selected_index: 1))

    expected_rows = [[8, "  alpha.rb"], [9, "> beta.rb"], [10, "  gamma.rb"]]
    expect(CursesPickerRenderSpecSupport.picker_writes(context.fetch(:writes))).to eq(expected_rows)
    expect(context.fetch(:screen).refresh_count).to eq(3)
  end
end

RSpec.describe Roded::Frontends::Curses, "picker candidate cleanup" do
  it "clears old candidate text when the replacement strings are shorter" do
    context = CursesPickerRenderSpecSupport.build_frontend
    frontend = context.fetch(:frontend)
    frontend.send(:render_layout, CursesPickerRenderSpecSupport.editor_snapshot)
    frontend.send(:show_picker, CursesPickerRenderSpecSupport.picker_payload(selected_index: 0))
    context.fetch(:clear_rows).clear
    context.fetch(:writes).clear
    payload = CursesPickerRenderSpecSupport.picker_payload(selected_index: 0, candidates: %w[a.rb b.rb c.rb])

    frontend.send(:show_picker, payload)

    expect(context.fetch(:clear_rows)).to eq([8, 9, 10])
    expected_rows = [[8, "> a.rb"], [9, "  b.rb"], [10, "  c.rb"]]
    expect(CursesPickerRenderSpecSupport.picker_writes(context.fetch(:writes))).to eq(expected_rows)
  end
end

RSpec.describe Roded::Frontends::Curses, "picker viewport height" do
  it "moves the modeline when filtering reduces the candidate list" do
    context = CursesPickerRenderSpecSupport.build_frontend
    frontend = context.fetch(:frontend)
    frontend.send(:render_layout, CursesPickerRenderSpecSupport.editor_snapshot)
    frontend.send(:show_picker, CursesPickerRenderSpecSupport.picker_payload(selected_index: 0))
    context.fetch(:writes).clear
    payload = CursesPickerRenderSpecSupport.picker_payload(selected_index: 0, candidates: ["beta.rb"])

    frontend.send(:show_picker, payload)

    expect(context.fetch(:modeline_rows).last).to eq(9)
    expect(CursesPickerRenderSpecSupport.picker_writes(context.fetch(:writes))).to eq([[10, "> beta.rb"]])
  end
end

RSpec.describe Roded::Frontends::Curses, "picker dismissal" do
  it "restores the full editor area after the picker closes" do
    context = CursesPickerRenderSpecSupport.build_frontend
    frontend = context.fetch(:frontend)
    frontend.send(:render_layout, CursesPickerRenderSpecSupport.editor_snapshot)
    frontend.send(:show_picker, CursesPickerRenderSpecSupport.picker_payload(selected_index: 0))
    context.fetch(:writes).clear

    frontend.send(:clear_minibuffer, {})

    expect(context.fetch(:modeline_rows).last).to eq(10)
    expect(CursesPickerRenderSpecSupport.picker_writes(context.fetch(:writes))).to be_empty
  end
end
