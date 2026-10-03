module Roded
  # A thread-safe, intentionally narrow interface to the live editor session.
  class RubyEditorAPI
    def initialize(application)
      @application = application
    end

    def snapshot = request(:snapshot)

    def buffers = request(:buffers)

    def current_buffer = request(:current_buffer)

    def windows = request(:windows)

    def repl_history = request(:repl_history)

    def insert_text(text) = request(:insert_text, text)

    def open_file(path) = request(:open_file, path)

    def save_file(path = nil) = request(:save_file, path)

    def switch_buffer(name) = request(:switch_buffer, name)

    def execute_command(name) = request(:execute_command, name)

    def register_command(name, binding: nil, description: nil, &action)
      request(:register_command, name, binding, description, action)
    end

    private

    def request(action, ...)
      @application.request_repl_api(action, ...)
    end
  end
end
