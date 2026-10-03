module Roded
  # Manages the interactive Ruby session attached to the editor.
  module RubyReplOperations
    def open_ruby_repl
      @ruby_repl_buffer = find_or_create_repl_buffer
      activate_buffer(@ruby_repl_buffer)
      append_repl_prompt if @ruby_repl_input_start.nil?
      ensure_ruby_repl_session
    end

    def evaluate_ruby_repl
      return unless in_ruby_repl_buffer?

      code = current_buffer.region_text(@ruby_repl_input_start, current_window.point)
      return display_message("REPL input is empty.") if code.empty?

      start_repl_evaluation(code)
    end

    def interrupt_ruby_repl
      return display_message("No Ruby expression is running.") unless @ruby_repl_session&.interrupt

      display_message("Interrupt requested.")
    end

    def cycle_ruby_repl_history(direction)
      return unless current_buffer.equal?(@ruby_repl_buffer) && @ruby_repl_session

      history = @ruby_repl_session.history
      return if history.empty?
      return if direction.positive? && @ruby_repl_history_index.nil?

      @ruby_repl_history_index ||= history.length
      entry = history_entry(history, direction)
      replace_repl_input(entry)
    end

    def request_repl_api(action, *arguments)
      return dispatch_repl_api(action, arguments) if @core_thread.nil? || Thread.current == @core_thread

      response = Queue.new
      push_event(Event.new(:repl_api_call, { action:, arguments:, response: }))
      success, value = response.pop
      raise value unless success

      value
    end

    private

    def in_ruby_repl_buffer?
      return true if current_buffer.equal?(@ruby_repl_buffer)

      display_message("Open *ruby* to evaluate code.")
      false
    end

    def ensure_ruby_repl_session
      return @ruby_repl_session if @ruby_repl_session

      @ruby_repl_session = create_ruby_repl_session
    end

    def start_repl_evaluation(code)
      return display_message("A Ruby expression is already running.") unless @ruby_repl_session.start_evaluation?(code)

      current_buffer.insert_text("\n")
      current_window.point = current_buffer.cursor_pos
      publish_ui_update(UIUpdate.new(:render, {}))
    end

    def find_or_create_repl_buffer
      buffers.find { |candidate| candidate.name == "*ruby*" } || create_repl_buffer
    end

    def create_repl_buffer
      buffer = Buffer.new("*ruby*")
      buffer.load_text("Roded Ruby REPL — C-c C-c evaluates; C-c C-k interrupts.\n> ")
      buffer.cursor_pos = { row: 1, col: 2 }
      add_buffer(buffer)
      @ruby_repl_input_start = { row: 1, col: 2 }
      buffer
    end

    def append_repl_prompt
      buffer = @ruby_repl_buffer
      buffer.cursor_pos = { row: buffer.lines.length - 1, col: buffer.lines.last.length }
      buffer.insert_text("> ")
      current_window.point = current_buffer.cursor_pos
      @ruby_repl_input_start = buffer.cursor_pos
    end

    def create_ruby_repl_session
      RubyReplSession.new(@ruby_editor_api) { |event| push_event(event) }
    end

    def history_entry(history, direction)
      direction.negative? ? previous_history_entry(history) : next_history_entry(history)
    end

    def previous_history_entry(history)
      @ruby_repl_history_draft ||= current_buffer.region_text(@ruby_repl_input_start, current_window.point)
      @ruby_repl_history_index = [@ruby_repl_history_index - 1, 0].max
      history[@ruby_repl_history_index]
    end

    def next_history_entry(history)
      @ruby_repl_history_index = [@ruby_repl_history_index + 1, history.length].min
      return @ruby_repl_history_draft.to_s if @ruby_repl_history_index == history.length

      history[@ruby_repl_history_index]
    end

    def replace_repl_input(entry)
      current_buffer.delete_region(@ruby_repl_input_start, current_window.point)
      current_buffer.insert_text(entry)
      current_window.point = current_buffer.cursor_pos
      publish_ui_update(UIUpdate.new(:render, {}))
    end
  end
end
