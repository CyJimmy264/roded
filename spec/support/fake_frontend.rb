class FakeFrontend
  attr_accessor :focus
  attr_writer :page_size
  attr_reader :commands, :messages, :renders, :buffers

  def initialize(page_size: 3)
    @commands = []
    @messages = []
    @renders = []
    @buffers = []
    @focus = nil
    self.page_size = page_size
  end

  def page_size(_window_id = nil)
    @page_size
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
end

class ScriptedFrontend
  attr_reader :closed

  def initialize(events = [])
    @events = Queue.new
    events.each { |event| @events << event }
  end

  define_method(:next_event) { @events.pop }

  def handle_command(command)
    @events << Roded::Event.new(:quit, {}) if command.type == :quit
  end

  def close
    @closed = true
  end
end

class EndOfInputFrontend
  attr_reader :closed

  define_method(:next_event) { nil }

  def handle_command(_command); end

  def close
    @closed = true
  end
end
