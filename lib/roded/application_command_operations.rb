module Roded
  # Owns the command catalog and command line execution API.
  module ApplicationCommandOperations
    def process_command(command)
      if command.to_s.empty?
        broadcast_command(Command.new(:render, {}))
      elsif !@command_registry.registered?(command)
        display_message("Unknown command: #{command}")
      else
        execute_command(command)
      end
    end

    def register_command(name, binding: nil, description: nil, &action)
      @command_registry.register(name, description:, &action)
      @keymap.bind(binding, type: :custom_command, payload: { name: name.to_s }) if binding
    end

    def command_names = @command_registry.names

    def command_catalog = @command_registry.catalog

    def execute_command(name) = @command_registry.call(name, self)

    private

    def register_builtin_commands
      register_simple_commands
      register_prompt_commands
      register_search_commands
      register_mode_and_repl_commands
    end

    def register_simple_commands
      @command_registry.register("quit", description: "Quit Roded", &:request_quit)
      @command_registry.register("describe-bindings", description: "Show active key bindings", &:describe_bindings)
      @command_registry.register("undo", description: "Undo the last edit", &:undo)
      @command_registry.register("redo", description: "Redo the last edit", &:redo)
      @command_registry.register("indent-region", description: "Indent selected lines by two spaces", &:indent)
      @command_registry.register("next-buffer", &:next_buffer)
      @command_registry.register("previous-buffer", &:previous_buffer)
      @command_registry.register("kill-buffer", &:kill_current_buffer)
    end

    def register_prompt_commands
      register_save_commands
      @command_registry.register("open", description: "Open a file") do |editor|
        editor.start_minibuffer(:open, "Open file: ")
      end
      @command_registry.register("switch-buffer") do |editor|
        editor.start_minibuffer(:switch_buffer, "Buffer name or path: ")
      end
    end

    def register_save_commands
      @command_registry.register("save", description: "Save the current buffer") do |editor|
        filename = editor.current_buffer&.filename
        filename ? editor.save_file(filename) : editor.start_minibuffer(:save, "Save file as: ")
      end
      @command_registry.register("save-as", description: "Save as another file") do |editor|
        editor.start_minibuffer(:save_as, "Save as: ")
      end
    end

    def register_search_commands
      @command_registry.register("isearch-forward", description: "Search forward") do |editor|
        editor.start_minibuffer(:search_forward, "Search forward: ")
      end
      @command_registry.register("isearch-backward", description: "Search backward") do |editor|
        editor.start_minibuffer(:search_backward, "Search backward: ")
      end
      @command_registry.register("goto-line", description: "Go to a line number") do |editor|
        editor.start_minibuffer(:goto_line, "Goto line: ")
      end
    end

    def register_mode_and_repl_commands
      @command_registry.register("set-major-mode", description: "Change syntax mode") do |editor|
        editor.start_minibuffer(:major_mode, "Major mode: ")
      end
      @command_registry.register("ruby-repl", description: "Open the in-process Ruby REPL", &:open_ruby_repl)
    end
  end
end
