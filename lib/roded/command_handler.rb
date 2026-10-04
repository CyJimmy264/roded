require_relative "command_handler_event_maps"

module Roded
  # Routes normalized editor events to their core operations.
  class CommandHandler
    include CommandHandlerEventMaps

    def initialize(context)
      @context = context
    end

    def handle(command)
      raise ArgumentError, "expected EditorCommand, got #{command.class}" unless command.is_a?(EditorCommand)

      @context.break_kill_sequence(command.type)
      return handle_minibuffer_event(command) if @context.focus == :minibuffer

      handle_buffer_event(command)
    end

    private

    def handle_buffer_event(event)
      handler = BUFFER_EVENT_ROUTES[event.type]
      method(handler).call(event) if handler
    end

    def move_buffer_cursor(event)
      method, render_type, option = CURSOR_ACTIONS.fetch(event.type)
      args = option == :page_size ? [@context.page_size] : []
      @context.invoke_buffer_operation(method, *args)
      payload = option && option != :page_size ? { direction: option } : {}
      @context.publish_ui_update(render_type, payload)
    end

    def scroll_viewport(event)
      direction = event.type.to_s.end_with?("up") ? -1 : 1
      distance = event.type.to_s.include?("page") ? @context.page_size : 1
      @context.scroll_viewport(direction * distance)
    end

    def scroll_by(event)
      @context.scroll_viewport(event.payload.fetch(:amount))
    end

    def operate_on_buffer(event)
      method, argument = BUFFER_OPERATIONS.fetch(event.type)
      args = buffer_operation_arguments(argument, event.payload)
      @context.invoke_buffer_operation(method, *args)
    end

    def buffer_operation_arguments(argument, payload)
      return [] unless argument
      return [@context.kill_ring] if argument == :kill_ring

      [payload.fetch(argument == :char ? :char : :text)]
    end

    def call_editor_action(event)
      method, *arguments = EDITOR_ACTIONS.fetch(event.type)
      @context.invoke_editor_action(method, *arguments)
    end

    def start_prompt(event)
      prompt = PROMPTS.fetch(event.type)
      @context.start_minibuffer(*prompt)
    end

    def execute_registered_command(event) = @context.execute_command(COMMANDS.fetch(event.type))

    def begin_query_replace(_event) = @context.begin_query_replace

    def execute_custom_command(event) = @context.execute_command(event.payload.fetch(:name))

    def render_event(_event) = @context.publish_ui_update(:render, { force_redraw: true })

    def ignore_event(_event); end

    def handle_minibuffer_event(event)
      return move_picker(event) if PICKER_MOVEMENTS.key?(event.type)
      return move_minibuffer(event) if MINIBUFFER_MOVEMENTS.key?(event.type)
      return edit_minibuffer(event) if MINIBUFFER_EDITS.key?(event.type)

      submit_minibuffer_event(event)
    end

    def move_picker(event)
      method, amount = PICKER_MOVEMENTS.fetch(event.type)
      @context.public_send(method, amount)
    end

    def move_minibuffer(event)
      @context.minibuffer.public_send(MINIBUFFER_MOVEMENTS.fetch(event.type))
      @context.render_minibuffer
    end

    def edit_minibuffer(event)
      method, argument = MINIBUFFER_EDITS.fetch(event.type)
      args = argument == :char ? [event.payload[:char]] : []
      @context.minibuffer.public_send(method, *args)
      @context.render_minibuffer
      @context.refresh_picker
    end

    def submit_minibuffer_event(event)
      case event.type
      when :cancel then @context.cancel_minibuffer
      when :enter then @context.submit_minibuffer
      when :noop then nil
      end
    end
  end
end
