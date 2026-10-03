module Roded
  # Manages minibuffer prompts, picker state, and submitted values.
  module ApplicationMinibufferOperations
    def start_minibuffer(kind, prompt)
      @minibuffer_kind = kind
      @picker = picker_for(kind)
      @focus = :minibuffer
      broadcast_focus
      @minibuffer.start(prompt)
      render_minibuffer
      render_picker
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
      @picker = nil
      cancel_query_replace if @query_replace_state
      @minibuffer_kind = nil
      clear_pending_close_state
      clear_pending_save_confirmation
      @focus = :buffer
      broadcast_focus
      broadcast_command(Command.new(:minibuffer_clear, {}))
      broadcast_command(Command.new(:render, {}))
    end

    def submit_minibuffer
      kind = @minibuffer_kind
      text = @minibuffer.submit
      @picker_query = @picker&.query
      return if resume_path_picker_if_directory?(kind)

      complete_minibuffer_submission(kind, selected_picker_value || text)
    end

    private

    def complete_minibuffer_submission(kind, text)
      @picker = nil
      @minibuffer_kind = nil
      @focus = :buffer
      broadcast_focus
      broadcast_command(Command.new(:minibuffer_clear, {}))
      minibuffer_submit_handler.handle(kind, text)
      @picker_query = nil
      broadcast_command(Command.new(:render, {}))
    end

    def resume_path_picker_if_directory?(kind)
      selected = selected_picker_value
      return false unless path_picker?(kind) && selected&.end_with?("/")
      return false unless File.directory?(File.expand_path(selected))

      continue_path_picker(selected, kind)
      true
    end

    def minibuffer_submit_handler
      @minibuffer_submit_handler ||= MinibufferSubmitHandler.new(self)
    end
  end
end
