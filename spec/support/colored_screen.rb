# Records the text and active attributes written by the curses renderer.
class ColoredScreen
  attr_reader :cells

  def initialize
    @cells = {}
    @attribute = nil
  end

  def maxy = 80
  def maxx = 160

  def setpos(row, column)
    @row = row
    @column = column
  end

  def addstr(text)
    text.each_char.with_index { |character, index| @cells[[@row, @column + index]] = [character, @attribute] }
  end

  def attron(attribute)
    previous = @attribute
    @attribute = attribute
    yield self
  ensure
    @attribute = previous
  end
end
