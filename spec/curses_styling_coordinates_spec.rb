require "roded/frontends/curses"
require_relative "support/colored_screen"

module CursesStylingCoordinatesHelpers
  def render_styled_line(line, tokens, screen_row:, left_column: 0, **overlays)
    screen = ColoredScreen.new
    frontend = styled_frontend(screen)
    item = { tokens: [tokens], mark: nil, point: { row: 0, col: 6 }, highlight: nil }.merge(overlays)
    context = Roded::Frontends::CursesRenderContext::BufferLine.new(
      item:, line:, buffer_row: 0, screen_row:, left: 0, width: screen.maxx, left_column:
    )
    frontend.send(:draw_buffer_line, context)
    screen.cells.sort.map(&:last)
  end

  def styled_frontend(screen)
    frontend = Roded::Frontends::Curses.allocate
    frontend.instance_variable_set(:@screen, screen)
    frontend.instance_variable_set(:@color_pairs, { string: :string, keyword: :keyword, symbol: :symbol })
    frontend.instance_variable_set(:@search_pair, :search)
    frontend
  end

  def expected_syntax_cells(line, tokens, left_column)
    line.chars.each_with_index.drop(left_column).map do |character, column|
      token = tokens.find { |span| column.between?(span[:start], span[:finish] - 1) }
      [character, token&.fetch(:category)]
    end
  end
end

RSpec.describe Roded::Frontends::Curses, "syntax coordinates after scrolling" do
  include CursesStylingCoordinatesHelpers

  it "paints actual Ruby tokens independently of screen row and horizontal origin" do
    allow(Curses).to receive(:color_pair) { |pair| pair }
    lines = File.readlines(File.join(__dir__, "application_spec.rb"), chomp: true)
    selected = lines.select do |line|
      line.include?("restores point when") || line.include?("instance_variable_set(:@file")
    end
    selected.each do |line|
      tokens = Roded::SyntaxHighlighter.new.spans(:ruby, [line]).first
      [0, 6, 41].product([0, 10, 40]).each do |row, origin|
        actual = render_styled_line(line, tokens, screen_row: row, left_column: origin)
        expect(actual).to eq(expected_syntax_cells(line, tokens, origin))
      end
    end
  end
end

RSpec.describe Roded::Frontends::Curses, "region and search coordinates" do
  include CursesStylingCoordinatesHelpers

  it "keeps selection styling within the selected columns on another screen row" do
    actual = render_styled_line("abcdef", [], screen_row: 10, mark: { row: 0, col: 3 })
    expect(actual.map(&:last)).to eq([nil, nil, nil, Curses::A_REVERSE, Curses::A_REVERSE, Curses::A_REVERSE])
  end

  it "keeps search styling within the matching columns after horizontal scrolling" do
    allow(Curses).to receive(:color_pair) { |pair| pair }
    highlight = { start: { row: 0, col: 4 }, finish: { row: 0, col: 6 } }
    actual = render_styled_line("abcdefgh", [], screen_row: 10, left_column: 2, highlight:)
    expect(actual.map(&:last)).to eq([nil, nil, :search, :search, nil, nil])
  end
end
