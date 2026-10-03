module Roded
  # Main application class: wires frontends and routes events either to the buffer
  # or the minibuffer depending on current focus.
  class Application
    include Logging
    include FileOperations
    include CloseOperations

    attr_reader :focus, :minibuffer, :kill_ring, :current_window
    SYSTEM_EVENTS = %i[quit signal frontend_eof frontend_failure].freeze

    def initialize
      @buffers = []
      @windows = []
      @window_layout = nil
      @frontends = []
      @frontend_threads = []
      @frontend_sources = {}
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
      initialize_lifecycle
      logger.info("Application initialized")
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

    def startup(paths = [])
      paths = Array(paths)
      if paths.empty?
        add_buffer(Buffer.new("*scratch*"))
        display_message("Edit text, C-x C-f opens a file, C-x C-s saves.")
      else
        paths.each { |path| open_file(path) }
      end
      add_buffer(Buffer.new("*scratch*")) unless current_buffer
      add_window(Window.new(current_buffer)) if current_buffer && @windows.empty?
    end

    def add_buffer(buffer)
      @buffers << buffer
      buffer.add_edit_observer(self)
      @current_buffer ||= buffer
      @frontends.each { |frontend| frontend.add_buffer(buffer) }
    end

    def add_window(window)
      if @window_layout
        @window_layout.split(@current_window, window, :vertical)
        @windows = @window_layout.windows
      else
        @window_layout = WindowLayout.new(window)
        @windows = [window]
      end
      @current_window ||= window
    end

    def windows
      @window_layout ? @window_layout.windows.freeze : [].freeze
    end

    def split_window(direction)
      return unless @current_window

      window = @current_window.copy
      @window_layout.split(@current_window, window, direction)
      @windows = @window_layout.windows
      @current_window = window
      @current_buffer = window.buffer
      render_active_window
      window
    end

    def other_window
      return if windows.length < 2

      index = windows.index(@current_window) || 0
      activate_window(windows[(index + 1) % windows.length])
    end

    def delete_window
      return display_message("Cannot delete the only window.") if windows.length < 2

      removed = @current_window
      @window_layout.remove(removed)
      @windows = @window_layout.windows
      activate_window(@windows.first)
    end

    def delete_other_windows
      return unless @current_window

      @window_layout.keep(@current_window)
      @windows = [@current_window]
      render_active_window
    end

    def set_status_bar(status_bar)
      @status_bar = status_bar
    end

    def add_frontend(frontend)
      @frontends << frontend
      register_frontend_source(frontend)
      prepare_frontend(frontend)
      sync_frontend(frontend)
    end

    def broadcast_command(command)
      if command.type == :render && current_window
        payload = command.payload.merge(editor_snapshot: editor_snapshot)
        command = Command.new(:render, payload.freeze)
      end
      logger.debug("broadcast_command: #{command.type}")
      @frontends.each { |f| f.handle_command(command) }
    end

    def editor_snapshot
      {
        tree: @window_layout.snapshot_tree,
        active_window_id: @current_window&.object_id,
        windows: windows.map { |window| window_snapshot(window) }.freeze
      }.freeze
    end

    def buffer_edited(buffer, position_change)
      windows.each do |window|
        window.transform_positions(position_change) if window.buffer.equal?(buffer)
      end
    end

    def push_event(event)
      @event_queue << event
    rescue ClosedQueueError
      nil
    end

    def trap_signals
      %w[HUP INT QUIT TERM].each do |sig|
        @signal_handlers[sig] = trap(sig) do |signal|
          push_event(Event.new(:signal, { signal: }))
        end
      end
    end

    def run(manage_signals: true)
      trap_signals if manage_signals
      start_frontend_threads
      main_loop
    ensure
      restore_signals if manage_signals
      @stop_requested = true
      shutdown_frontends
    end

    def restore_signal_handlers
      restore_signals
    end

    def handle_event(event)
      logger.debug("handle_event: #{event.type}")
      logger.debug("handle_event: focus: #{@focus}")
      return request_quit(force: true) if SYSTEM_EVENTS.include?(event.type)
      return request_quit if event.type == :close_request

      target_window = windows.find { |window| window.object_id == event.payload[:window_id] }
      activate_window(target_window) if target_window && !target_window.equal?(@current_window)
      window_before = @current_window
      buffer_before = current_buffer
      buffer_before.cursor_pos = window_before.point if window_before && buffer_before
      @active_source_id = event.payload.fetch(:source_id, :default)
      routed_event = route_input_event(event)
      @command_handler.handle(routed_event) if routed_event
      if window_before && @current_window.equal?(window_before) && current_buffer.equal?(buffer_before)
        window_before.point = buffer_before.cursor_pos
      end
      broadcast_command(Command.new(:render, {})) if windows.length > 1
    ensure
      @active_source_id = nil
    end

    def process_command(command)
      case command
      when "open"
        start_minibuffer(:open, "Open file: ")
      when "save"
        start_minibuffer(:save, "Save file as: ")
      when "quit"
        request_quit
      when "undo"
        undo
      when "redo"
        self.redo
      when "", nil
        broadcast_command(Command.new(:render, {}))
      else
        display_message("Unknown command: #{command}")
      end
    end

    def current_buffer
      @current_window&.buffer || @current_buffer || @buffers.first
    end

    def buffers
      @buffers.dup.freeze
    end

    def undo
      changed = current_buffer&.undo
      broadcast_command(Command.new(:render, {})) if changed
      changed
    end

    def redo
      changed = current_buffer&.redo
      broadcast_command(Command.new(:render, {})) if changed
      changed
    end

    def next_buffer
      activate_relative_buffer(1)
    end

    def previous_buffer
      activate_relative_buffer(-1)
    end

    def switch_buffer(name)
      buffer = @buffers.find { |candidate| candidate.name == name || candidate.filename == name }
      return display_message("No buffer named '#{name}'.") unless buffer

      activate_buffer(buffer, message: "Switched to '#{name}'.")
    end

    def page_size
      frontend = @frontends.find { |candidate| @frontend_sources[candidate] == @active_source_id }
      frontend ||= @frontends.first
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
      @minibuffer_kind = nil
      clear_pending_close_state
      clear_pending_save_confirmation
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
      minibuffer_submit_handler.handle(kind, text)
      broadcast_command(Command.new(:render, {}))
    end

    private

    def minibuffer_submit_handler
      @minibuffer_submit_handler ||= MinibufferSubmitHandler.new(self)
    end

    def activate_loaded_file(result)
      buffer = Buffer.new(result.path)
      buffer.load_text(result.content)
      buffer.filename = result.path
      buffer.file_revision = result.revision
      add_buffer(buffer)
      @current_buffer = buffer
      @current_window.buffer = buffer if @current_window
      buffer.cursor_pos = @current_window.point if @current_window
      @frontends.each { |frontend| frontend.render(buffer) }
      broadcast_command(Command.new(:render, {}))
      display_message("File '#{result.path}' opened.")
    end

    def activate_buffer(buffer, message: nil)
      @current_buffer = buffer
      @current_window.buffer = buffer if @current_window
      buffer.cursor_pos = @current_window.point if @current_window
      @frontends.each { |frontend| frontend.render(buffer) }
      broadcast_command(Command.new(:render, {}))
      display_message(message) if message
    end

    def activate_window(window)
      @current_window = window
      @current_buffer = window.buffer
      @current_buffer.cursor_pos = window.point
      render_active_window
    end

    def render_active_window
      @frontends.each { |frontend| frontend.render(current_buffer) }
      broadcast_command(Command.new(:render, {}))
    end

    def window_snapshot(window)
      buffer = window.buffer
      {
        id: window.object_id,
        text: buffer.to_s.dup.freeze,
        lines: buffer.lines.map { |line| line.dup.freeze }.freeze,
        point: window.point.dup.freeze,
        mark: window.mark&.dup&.freeze,
        name: (buffer.filename || buffer.name || "*scratch*").to_s.dup.freeze,
        top_line: window.top_line,
        left_column: window.left_column,
        active: window.equal?(@current_window)
      }.freeze
    end

    def activate_relative_buffer(direction)
      return if @buffers.empty?

      index = @buffers.index(current_buffer) || 0
      activate_buffer(@buffers[(index + direction) % @buffers.length])
    end

    def main_loop
      until @stop_requested
        event = @event_queue.pop
        break unless event

        logger.debug("main_loop: event received: #{event.type} #{event.payload.inspect if event.respond_to?(:payload)}")
        handle_event(event)

      end
    rescue StandardError => e
      logger.error("Editor runtime failed: #{e.class}: #{e.message}")
      raise
    end

    def start_frontend_threads
      @frontends.each do |frontend|
        source_id = @frontend_sources.fetch(frontend)
        @frontend_threads << Thread.new { read_frontend_events(frontend, source_id) }
      end
    end

    def read_frontend_events(frontend, source_id)
      loop { break unless read_and_push_frontend_event(frontend, source_id) }
    rescue StandardError => e
      push_event(Event.new(:frontend_failure, { error: e, source_id: }))
    end

    def read_and_push_frontend_event(frontend, source_id)
      event = frontend.next_event
      return push_event(Event.new(:frontend_eof, { frontend: frontend.class.name })) && false unless event

      push_event(Event.new(event.type, event.payload.merge(source_id:)))
      !SYSTEM_EVENTS.include?(event.type)
    end

    def register_frontend_source(frontend)
      source_id = frontend.respond_to?(:input_source_id) ? frontend.input_source_id : frontend.object_id
      @frontend_sources[frontend] = source_id
    end

    def prepare_frontend(frontend)
      frontend.keymap = @keymap if frontend.respond_to?(:keymap=)
      frontend.focus = @focus if frontend.respond_to?(:focus=)
      @buffers.each { |buffer| frontend.add_buffer(buffer) }
    end

    def sync_frontend(frontend)
      frontend.render(current_buffer) if current_buffer && frontend.respond_to?(:render)
      return unless @focus == :minibuffer && frontend.respond_to?(:handle_command)

      frontend.handle_command(Command.new(:minibuffer_render, minibuffer_snapshot))
    end

    def minibuffer_snapshot
      { prompt: @minibuffer.prompt, text: @minibuffer.text, cursor: @minibuffer.cursor }
    end

    def route_input_event(event)
      return event unless event.type == :key

      routed = @command_router.route(event.payload[:key], source_id: @active_source_id)
      return unless routed
      if routed.type == :prefix_pending
        display_message("#{routed.payload[:prefix]} …")
        return
      end
      if routed.payload[:invalid_sequence]
        display_message("Unknown key sequence: #{routed.payload[:invalid_sequence]}")
        return
      end

      routed
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

    def restore_signals
      @signal_handlers.each { |signal, handler| trap(signal, handler) }
      @signal_handlers.clear
    end

    def shutdown_frontends
      notify_frontends_of_shutdown
      @frontend_threads.each(&:join)
      close_frontends
    ensure
      @event_queue.close unless @event_queue.closed?
    end

    def initialize_lifecycle
      @stop_requested = false
      @signal_handlers = {}
    end

    def notify_frontends_of_shutdown
      @frontends.each do |frontend|
        frontend.handle_command(Command.new(:quit, {}))
      rescue StandardError => e
        logger.warn("Frontend shutdown notification failed: #{e.class}: #{e.message}")
      end
    end

    def close_frontends
      @frontends.each do |frontend|
        frontend.close if frontend.respond_to?(:close)
      rescue StandardError => e
        logger.warn("Frontend close failed: #{e.class}: #{e.message}")
      end
    end
  end
end
