module Roded
  # Main application class: wires frontends and routes events either to the buffer
  # or the minibuffer depending on current focus.
  class Application
    include Logging
    attr_reader :focus, :minibuffer, :kill_ring

    def initialize
      @buffers = []
      @windows = []
      @frontends = []
      @frontend_threads = []
      @event_queue = Queue.new
      @status_bar = nil
      @minibuffer = Minibuffer.new
      @minibuffer_kind = nil
      @focus = :buffer
      @keymap = Keymap.load
      @kill_ring = KillRing.new
      @current_buffer = nil
      @command_router = CommandRouter.new(@keymap)
      @command_handler = CommandHandler.new(self)
      logger.info("Application initialized")
      trap_signals
    end



    def welcome
      welcome_buffer = Buffer.new("Welcome")
      welcome_buffer.lines = [
        "Welcome to Roded!",
        "",
        "Press any key to get started.",
        "",
        "This is a read-only welcome buffer."
      ]
      welcome_buffer.readonly = true
      add_buffer(welcome_buffer)
      add_window(Window.new(welcome_buffer))
    end

    def add_buffer(buffer)
      @buffers << buffer
      @current_buffer ||= buffer
      @frontends.each { |frontend| frontend.add_buffer(buffer) }
    end

    def add_window(window)
      @windows << window
    end

    def set_status_bar(status_bar)
      @status_bar = status_bar
    end

    def add_frontend(frontend)
      @frontends << frontend
      frontend.keymap = @keymap if frontend.respond_to?(:keymap=)
      frontend.focus = @focus if frontend.respond_to?(:focus=)
      @buffers.each { |buffer| frontend.add_buffer(buffer) }
      thread = Thread.new do
        loop do
          event = frontend.get_event
          next unless event

          push_event(event)
          break if event.type == :quit
        rescue StandardError => e
          warn "Frontend thread error: #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
          break
        end
      end
      @frontend_threads << thread
    end

    def broadcast_command(command)
      logger.debug("broadcast_command: #{command.type}")
      @frontends.each { |f| f.handle_command(command) }
    end

    def push_event(event)
      @event_queue << event
    rescue ClosedQueueError
      nil
    end

    def trap_signals
      %w[HUP INT QUIT TERM].each do |sig|
        prev = trap(sig) do |signal|
          push_event(Event.new(:signal, { signal: }))
        end

        trap(sig, "IGNORE") if prev == "IGNORE"
      end
    end

    def run
      main_thread = Thread.new { main_loop }
      main_thread.join

      @frontends.each { |f| f.close if f.respond_to?(:close) }
      @event_queue.close

      @frontend_threads.each(&:join)
    end

    def handle_event(event)
      logger.debug("handle_event: #{event.type}")
      logger.debug("handle_event: focus: #{@focus}")
      if event.type == :key
        routed = @command_router.route(event.payload[:key])
        return unless routed

        return handle_event(routed)
      end
      @command_handler.handle(event)
    end

    def process_command(command)
      case command
      when "open"
        start_minibuffer(:open, "Open file: ")
      when "save"
        start_minibuffer(:save, "Save file as: ")
      when "quit"
        broadcast_command(Command.new(:quit, {}))
      when "", nil
        broadcast_command(Command.new(:render, {}))
      else
        display_message("Unknown command: #{command}")
      end
    end

    def open_file(filename)
      content = File.read(filename)
      buffer = Buffer.new(filename)
      buffer.lines = content.lines.map(&:chomp)
      buffer.filename = filename
      buffer.cursor_pos = { row: 0, col: 0 }
      buffer.readonly = false
      add_buffer(buffer)
      @current_buffer = buffer
      @frontends.each { |frontend| frontend.render(@current_buffer) }
      display_message("File '#{filename}' opened.")
    rescue Errno::ENOENT
      display_message("File not found: #{filename}")
    rescue StandardError => e
      display_message("Error opening file: #{e.message}")
    end

    def save_file(filename)
      buffer = current_buffer
      return unless buffer

      File.write(filename, buffer.to_s)
      buffer.filename = filename
      display_message("File '#{filename}' saved.")
    rescue StandardError => e
      display_message("Error saving file: #{e.message}")
    end

    def current_buffer
      @current_buffer || @buffers.first
    end

    def page_size
      frontend = @frontends.first
      return 1 unless frontend && frontend.respond_to?(:page_size)

      [frontend.page_size.to_i, 1].max
    end

    def start_minibuffer(kind, prompt)
      @minibuffer_kind = kind
      @focus = :minibuffer
      broadcast_focus
      @minibuffer.start(prompt)
      render_minibuffer
    end

    def render_minibuffer
      broadcast_command(
        Command.new(
          :minibuffer_render,
          { prompt: @minibuffer.prompt, text: @minibuffer.text, cursor: @minibuffer.cursor }
        )
      )
    end

    def cancel_minibuffer
      @minibuffer.cancel
      @focus = :buffer
      broadcast_focus
      broadcast_command(Command.new(:minibuffer_clear, {}))
      broadcast_command(Command.new(:render, {}))
    end

    def submit_minibuffer
      text = @minibuffer.submit
      kind = @minibuffer_kind
      @minibuffer_kind = nil
      @focus = :buffer
      broadcast_focus
      broadcast_command(Command.new(:minibuffer_clear, {}))

      case kind
      when :command
        process_command(text)
      when :open
        open_file(text) if text && !text.empty?
      when :save
        save_file(text) if text && !text.empty?
      end
      broadcast_command(Command.new(:render, {}))
    end

    private

    def main_loop
      loop do
        event = @event_queue.pop
        next unless event

        logger.debug("main_loop: event received: #{event.type} #{event.payload.inspect if event.respond_to?(:payload)}")
        handle_event(event)

        if event.type == :quit
          logger.debug("main_loop: break on quit")
          break
        end
      end
    end

    def display_message(message)
      @frontends.each do |frontend|
        frontend.display_message(message) if frontend.respond_to?(:display_message)
      end
    end

    def broadcast_focus
      @frontends.each do |frontend|
        frontend.focus = @focus if frontend.respond_to?(:focus=)
      end
    end
  end
end
