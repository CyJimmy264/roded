module Roded
  # Adapts the command handler's small operation API to Application services.
  class ApplicationCommandContext
    def initialize(application)
      @application = application
    end

    def focus = @application.focus

    def minibuffer = @application.minibuffer

    def kill_ring = @application.kill_ring

    def current_buffer = @application.current_buffer

    def page_size = @application.page_size

    def break_kill_sequence(command_type)
      @application.kill_ring.break_sequence unless %i[kill_line kill_region].include?(command_type)
    end

    def scroll_viewport(amount) = @application.scroll_viewport(amount)

    def move_picker(amount) = @application.move_picker(amount)

    def move_picker_history(amount) = @application.move_picker_history(amount)

    def start_minibuffer(kind, prompt) = @application.start_minibuffer(kind, prompt)

    def publish_ui_update(type, payload)
      @application.publish_ui_update(UIUpdate.new(type, payload))
    end

    def invoke_buffer_operation(method, *)
      @application.current_buffer&.public_send(method, *)
    end

    def invoke_editor_action(method, *)
      @application.public_send(method, *)
    end

    def execute_command(name) = @application.execute_command(name)

    def begin_query_replace = @application.begin_query_replace

    def render_minibuffer = @application.render_minibuffer

    def refresh_picker = @application.refresh_picker

    def cancel_minibuffer = @application.cancel_minibuffer

    def submit_minibuffer = @application.submit_minibuffer
  end
end
