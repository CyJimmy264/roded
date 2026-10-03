module Roded
  # Main application class: wires frontends and routes events either to the buffer
  # or the minibuffer depending on current focus.
  class Application
    include Logging
    include FileReloadOperations
    include FileOperations
    include CloseOperations
    include PickerOperations
    include PickerProviderOperations
    include SearchOperations
    include QueryReplaceOperations
    include RubyReplOperations
    include RubyReplEventOperations
    include RubyReplOutputOperations
    include BufferEditingOperations
    include KillRingOperations
    include TextCommandOperations
    include TabConversionOperations
    include HelpOperations
    include ApplicationCommandOperations
    include ApplicationMinibufferOperations
    include ApplicationInputRouting
    include WindowLayoutOperations
    include BufferNavigationOperations
    include EditorSnapshotOperations
    include ApplicationInputEventOperations
    include FrontendOperations
    include ApplicationSignalOperations
    include ApplicationRuntimeOperations
    include ApplicationSetupOperations

    attr_reader :focus, :minibuffer, :kill_ring, :session
    attr_writer :status_bar

    SYSTEM_EVENTS = %i[quit signal frontend_eof frontend_failure].freeze

    def initialize
      initialize_editor_state
      register_builtin_commands
      initialize_lifecycle
      logger.info("Application initialized")
    end

    def current_buffer
      session.current_window&.buffer || session.buffers.first
    end

    def current_window
      session.current_window
    end

    def current_window=(window)
      session.current_window = window
    end

    def welcome
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
      ensure_startup_buffer_and_window
      publish_ui_update(UIUpdate.new(:render, {}))
      display_configuration_warning
    end

    def add_buffer(buffer)
      session.add_buffer(buffer)
      buffer.add_edit_observer(self)
      @frontends.each { |frontend| frontend.add_buffer(buffer) if frontend.respond_to?(:add_buffer) }
    end

    def change_major_mode(mode)
      normalized = mode.to_s.downcase.to_sym
      return display_message("Unknown mode: #{mode}") unless SyntaxHighlighter::MODES.include?(normalized)

      current_buffer.major_mode = normalized
      publish_ui_update(UIUpdate.new(:render, {}))
    end

    private

    def display_configuration_warning
      display_message(@configuration_warning) if @configuration_warning
    end

    def ensure_startup_buffer_and_window
      add_buffer(Buffer.new("*scratch*")) unless current_buffer
      add_window(Window.new(current_buffer)) if current_buffer && windows.empty?
    end
  end
end
