module Roded
  # Main application class: wires frontends and routes events either to the buffer
  # or the minibuffer depending on current focus.
  class Application
    include Logging

    attr_reader :focus, :minibuffer, :kill_ring
    SYSTEM_EVENTS = %i[quit signal frontend_eof frontend_failure].freeze

    def initialize
      @buffers = []
      @windows = []
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
      @pending_close_action = nil
      @pending_close_buffers = []
      @pending_save_confirmation = nil
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
      register_frontend_source(frontend)
      prepare_frontend(frontend)
      sync_frontend(frontend)
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

      @active_source_id = event.payload.fetch(:source_id, :default)
      routed_event = route_input_event(event)
      @command_handler.handle(routed_event) if routed_event
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
      when "", nil
        broadcast_command(Command.new(:render, {}))
      else
        display_message("Unknown command: #{command}")
      end
    end

    def open_file(filename)
      identity = file_service.path_identity(filename)
      existing_buffer = @buffers.find { |buffer| buffer.filename == identity }
      return activate_buffer(existing_buffer, message: "File '#{identity}' is already open.") if existing_buffer

      result = File.file?(identity) ? file_service.read(identity) : file_service.create_new(identity)
      activate_loaded_file(result)
    rescue Errno::ENOENT
      display_message("File not found: #{filename}")
    rescue StandardError => e
      display_message("Error opening file: #{e.message}")
    end

    def save_file(filename, overwrite: false)
      buffer = current_buffer
      return unless buffer

      save_buffer_document(buffer, filename, overwrite:)
    end

    def current_buffer
      @current_buffer || @buffers.first
    end

    def buffers
      @buffers.dup.freeze
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

    def kill_current_buffer
      buffer = current_buffer
      return unless buffer

      if buffer.modified?
        begin_close_action(:kill, [buffer])
      else
        remove_buffer(buffer)
      end
    end

    def request_quit(force: false)
      return if @stop_requested
      if force
        @pending_close_action = nil
        @pending_close_buffers = []
        return finish_quit
      end
      return if @pending_close_action

      dirty_buffers = @buffers.select(&:modified?)
      return finish_quit if dirty_buffers.empty?

      begin_close_action(:quit, dirty_buffers)
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
      @pending_close_action = nil
      @pending_close_buffers = []
      @pending_save_confirmation = nil
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
      when :save, :save_as
        save_file(text) if text && !text.empty?
      when :switch_buffer
        switch_buffer(text) if text && !text.empty?
      when :kill_buffer
        kill_current_buffer
      when :close_confirmation
        handle_close_confirmation(text)
      when :close_save_as
        text && !text.empty? ? save_pending_close_buffer(text) : cancel_pending_close
      when :overwrite_confirmation
        handle_overwrite_confirmation(text)
      end
      broadcast_command(Command.new(:render, {}))
    end

    private

    def activate_loaded_file(result)
      buffer = Buffer.new(result.path)
      buffer.load_text(result.content)
      buffer.filename = result.path
      buffer.file_revision = result.revision
      add_buffer(buffer)
      @current_buffer = buffer
      @frontends.each { |frontend| frontend.render(buffer) }
      display_message("File '#{result.path}' opened.")
    end

    def activate_buffer(buffer, message: nil)
      @current_buffer = buffer
      @frontends.each { |frontend| frontend.render(buffer) }
      display_message(message) if message
    end

    def activate_relative_buffer(direction)
      return if @buffers.empty?

      index = @buffers.index(current_buffer) || 0
      @current_buffer = @buffers[(index + direction) % @buffers.length]
      @frontends.each { |frontend| frontend.render(@current_buffer) }
    end

    def begin_close_action(kind, buffers)
      @pending_close_action = { kind:, buffer: current_buffer }
      @pending_close_buffers = buffers.dup
      start_minibuffer(:close_confirmation, "Unsaved changes: save, discard, or cancel? (s/d/c) ")
    end

    def handle_close_confirmation(response)
      case response.to_s.strip.downcase
      when "s", "save"
        save_next_close_buffer
      when "d", "discard"
        finish_pending_close
      when "c", "cancel", ""
        cancel_minibuffer
      else
        display_message("Choose save, discard, or cancel.")
        start_minibuffer(:close_confirmation, "Unsaved changes: save, discard, or cancel? (s/d/c) ")
      end
    end

    def save_next_close_buffer
      buffer = @pending_close_buffers.shift
      return finish_pending_close unless buffer

      if buffer.filename
        continue_close_after_save(buffer, buffer.filename)
      else
        @pending_save_buffer = buffer
        start_minibuffer(:close_save_as, "Save #{buffer.name || "buffer"} as: ")
      end
    end

    def save_pending_close_buffer(filename)
      buffer = @pending_save_buffer
      @pending_save_buffer = nil
      continue_close_after_save(buffer, filename)
    end

    def continue_close_after_save(buffer, filename)
      saved = save_buffer_document(buffer, filename)
      return if @pending_save_confirmation
      return cancel_pending_close unless saved

      save_next_close_buffer
    end

    def save_buffer_document(buffer, filename, overwrite: false)
      if !overwrite && overwrite_confirmation_needed?(buffer, filename)
        request_overwrite_confirmation(buffer, filename, "Overwrite existing file '#{filename}'? (y/n) ")
        return false
      end

      result = write_buffer(buffer, filename, overwrite:)
      buffer.filename = result.path
      buffer.file_revision = result.revision
      buffer.mark_saved
      display_message("File '#{result.path}' saved.")
      true
    rescue FileService::Conflict => e
      request_overwrite_confirmation(buffer, filename, "#{e.message}. Overwrite? (y/n) ")
      false
    rescue StandardError => e
      display_message("Error saving file: #{e.message}")
      false
    end

    def overwrite_confirmation_needed?(buffer, filename)
      same_file = buffer.filename && file_service.path_identity(filename) == buffer.filename
      !same_file && (File.exist?(filename) || File.symlink?(filename))
    end

    def request_overwrite_confirmation(buffer, filename, prompt)
      @pending_save_confirmation = { buffer:, filename: }
      start_minibuffer(:overwrite_confirmation, prompt)
    end

    def handle_overwrite_confirmation(response)
      pending = @pending_save_confirmation
      return unless pending

      case response.to_s.strip.downcase
      when "y", "yes", "overwrite"
        @pending_save_confirmation = nil
        saved = save_buffer_document(pending.fetch(:buffer), pending.fetch(:filename), overwrite: true)
        save_next_close_buffer if saved && @pending_close_action
      when "n", "no", "c", "cancel", ""
        @pending_save_confirmation = nil
        @pending_close_action ? cancel_pending_close : display_message("Save cancelled.")
      else
        display_message("Choose yes to overwrite or no to cancel.")
        start_minibuffer(:overwrite_confirmation, "Overwrite file? (y/n) ")
      end
    end

    def finish_pending_close
      action = @pending_close_action
      @pending_close_action = nil
      @pending_close_buffers = []
      @pending_save_buffer = nil
      action[:kind] == :kill ? remove_buffer(action[:buffer]) : finish_quit
    end

    def cancel_pending_close
      @pending_close_action = nil
      @pending_close_buffers = []
      @pending_save_buffer = nil
      @focus = :buffer
      broadcast_focus
      broadcast_command(Command.new(:minibuffer_clear, {}))
      broadcast_command(Command.new(:render, {}))
    end

    def remove_buffer(buffer)
      @buffers.delete(buffer)
      @frontends.each { |frontend| frontend.remove_buffer(buffer) if frontend.respond_to?(:remove_buffer) }
      add_buffer(Buffer.new("*scratch*")) if @buffers.empty?
      @current_buffer = @buffers.first
      @windows.each { |window| window.buffer = @current_buffer if window.buffer == buffer }
      @frontends.each { |frontend| frontend.render(@current_buffer) }
      display_message("Buffer killed.")
    end

    def finish_quit
      @stop_requested = true
      broadcast_command(Command.new(:quit, {}))
    end

    def file_service
      @file_service ||= FileService.new
    end

    def file_revision_for(buffer, filename)
      same_file = buffer.filename && file_service.path_identity(filename) == buffer.filename
      return buffer.file_revision if same_file
      return if File.exist?(filename) || File.symlink?(filename)

      FileService::ABSENT_REVISION
    end

    def write_buffer(buffer, filename, overwrite: false)
      expected_revision = overwrite ? nil : file_revision_for(buffer, filename)
      file_service.write(filename, buffer.to_s, expected_revision:)
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
