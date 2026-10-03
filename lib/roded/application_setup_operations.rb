module Roded
  # Initializes the application subsystems and constructs the welcome buffer.
  module ApplicationSetupOperations
    private

    def initialize_editor_state
      initialize_document_state
      initialize_frontend_state
      initialize_service_state
      initialize_repl_state
      initialize_input_state
    end

    def initialize_document_state
      @session = EditorSession.new
      @kill_ring = KillRing.new
      @last_yank = nil
    end

    def initialize_frontend_state
      @frontends = []
      @frontend_threads = []
      @frontend_sources = {}
      @event_queue = Queue.new
      @status_bar = nil
    end

    def initialize_service_state
      @minibuffer = Minibuffer.new
      @minibuffer_kind = nil
      @picker = nil
      @picker_query_history = {}
      @focus = :buffer
      @keymap = Keymap.load
      @configuration_warning = @keymap.load_warning
      @command_registry = CommandRegistry.new
      @file_path_provider = FilePathProvider.new
      @syntax_highlighter = SyntaxHighlighter.new
    end

    def initialize_repl_state
      @ruby_editor_api = RubyEditorAPI.new(self)
      @ruby_repl_buffer = nil
      @ruby_repl_session = nil
      @ruby_repl_input_start = nil
      @ruby_repl_history_index = nil
      @ruby_repl_history_draft = nil
    end

    def initialize_input_state
      @command_router = CommandRouter.new(@keymap)
      @command_handler = CommandHandler.new(ApplicationCommandContext.new(self))
    end

    def welcome_buffer
      buffer = Buffer.new("Welcome")
      buffer.lines = [
        "Welcome to Roded!",
        "",
        "Press any key to get started.",
        "",
        "This is a read-only welcome buffer."
      ]
      buffer.readonly = true
      buffer
    end
  end
end
