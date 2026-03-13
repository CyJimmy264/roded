class FakeFrontend
  attr_accessor :focus
  attr_reader :commands, :messages, :renders, :buffers

  def initialize
    @commands = []
    @messages = []
    @renders = []
    @buffers = []
    @focus = nil
  end

  def add_buffer(buffer)
    buffers << buffer
  end

  def handle_command(command)
    commands << command
  end

  def display_message(message)
    messages << message
  end

  def render(buffer)
    renders << buffer
  end

  def page_size
    3
  end
end
