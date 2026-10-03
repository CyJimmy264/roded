require_relative "command_handler_event_maps"

module Roded
  # Routes normalized editor events to their core operations.
  class CommandHandler
    include CommandHandlerEventMaps

    def initialize(editor)
      @editor = editor
    end

    def handle(event)
      @editor.kill_ring.break_sequence unless %i[kill_line kill_region].include?(event.type)
      return handle_minibuffer_event(event) if @editor.focus == :minibuffer

      handle_buffer_event(event)
    end

    private

    def handle_buffer_event(event)
      handler = BUFFER_EVENT_ROUTES[event.type]
      method(handler).call(event) if handler
    end

    def move_buffer_cursor(event)
      method, render_type, option = CURSOR_ACTIONS.fetch(event.type)
      args = option == :page_size ? [@editor.page_size] : []
      @editor.current_buffer&.public_send(method, *args)
      payload = option && option != :page_size ? { direction: option } : {}
      @editor.broadcast_command(Command.new(render_type, payload))
    end

    def scroll_viewport(event)
      direction = event.type.to_s.end_with?("up") ? -1 : 1
      distance = event.type.to_s.include?("page") ? @editor.page_size : 1
      @editor.scroll_viewport(direction * distance)
    end

    def scroll_by(event)
      @editor.scroll_viewport(event.payload.fetch(:amount))
    end

    def operate_on_buffer(event)
      method, argument = BUFFER_OPERATIONS.fetch(event.type)
      args = buffer_operation_arguments(argument, event.payload)
      @editor.current_buffer&.public_send(method, *args)
      @editor.broadcast_command(Command.new(:render, {})) if event.type == :kill_line
    end

    def buffer_operation_arguments(argument, payload)
      return [] unless argument
      return [@editor.kill_ring] if argument == :kill_ring

      [payload.fetch(argument == :char ? :char : :text)]
    end

    def call_editor_action(event)
      method, *arguments = EDITOR_ACTIONS.fetch(event.type)
      @editor.public_send(method, *arguments)
    end

    def start_prompt(event)
      prompt = PROMPTS.fetch(event.type)
      @editor.start_minibuffer(*prompt)
    end

    def execute_registered_command(event) = @editor.execute_command(COMMANDS.fetch(event.type))

    def begin_query_replace(_event) = @editor.begin_query_replace

    def execute_custom_command(event) = @editor.execute_command(event.payload.fetch(:name))

    def render_event(_event) = @editor.broadcast_command(Command.new(:render, {}))

    def ignore_event(_event); end

    def handle_minibuffer_event(event)
      return move_picker(event) if PICKER_MOVEMENTS.key?(event.type)
      return move_minibuffer(event) if MINIBUFFER_MOVEMENTS.key?(event.type)
      return edit_minibuffer(event) if MINIBUFFER_EDITS.key?(event.type)

      submit_minibuffer_event(event)
    end

    def move_picker(event)
      method, amount = PICKER_MOVEMENTS.fetch(event.type)
      @editor.public_send(method, amount)
    end

    def move_minibuffer(event)
      @editor.minibuffer.public_send(MINIBUFFER_MOVEMENTS.fetch(event.type))
      @editor.render_minibuffer
    end

    def edit_minibuffer(event)
      method, argument = MINIBUFFER_EDITS.fetch(event.type)
      args = argument == :char ? [event.payload[:char]] : []
      @editor.minibuffer.public_send(method, *args)
      @editor.render_minibuffer
      @editor.refresh_picker
    end

    def submit_minibuffer_event(event)
      case event.type
      when :cancel then @editor.cancel_minibuffer
      when :enter then @editor.submit_minibuffer
      when :noop then nil
      end
    end
  end
end
