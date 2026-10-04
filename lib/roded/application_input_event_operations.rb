module Roded
  # Dispatches frontend input to the active view and shared buffer.
  module ApplicationInputEventOperations
    SNAPSHOT_REFRESH_EVENTS = %i[
      move_down move_up move_left move_right move_word_forward move_word_backward
      document_start document_end page_down page_up line_start line_end
      insert_char backspace delete enter paste kill_line kill_region yank yank_pop undo redo
    ].freeze

    def handle_event(event)
      validate_input_event(event)
      batch_ui_updates do
        special_input_event?(event) ? dispatch_special_input_event(event) : process_frontend_input(event)
      end
    ensure
      clear_active_input_context
    end

    private

    def validate_input_event(event)
      raise ArgumentError, "expected InputEvent, got #{event.class}" unless event.is_a?(InputEvent)
    end

    def clear_active_input_context
      @active_source_id = nil
      @active_page_size = nil
      @active_page_window_id = nil
    end

    def handle_mouse_selection(event)
      activate_target_window(event)
      prepare_input_context(event, current_window)
      return unless current_window

      apply_mouse_selection(event)
      ensure_current_point_visible
      publish_ui_update(UIUpdate.new(:render, {}))
    end

    def apply_mouse_selection(event)
      window = current_window
      @focus = :buffer
      window.point = event.payload.fetch(:point)
      window.mark = event.payload[:mark]
      window.buffer.break_typing_undo_group
    end

    def handle_resize_event
      ensure_current_point_visible
      publish_ui_update(UIUpdate.new(:render, {}))
    end

    def handle_horizontal_scroll(event)
      window = windows.find { |candidate| candidate.object_id == event.payload[:window_id] }
      return unless window

      update_horizontal_origin(window, event.payload)
      activate_window(window) unless window.equal?(current_window)
    end

    def update_horizontal_origin(window, payload)
      maximum = window.buffer.maximum_line_length
      window.left_column = payload.fetch(:left_column).to_i.clamp(0, maximum)
    end

    def process_frontend_input(event)
      log_input_event(event)
      activate_target_window(event)
      refresh_snapshot = @focus == :buffer
      window_before = current_window
      prepare_input_context(event, window_before)
      routed_event = dispatch_routed_input(event)
      ensure_current_point_visible
      publish_ui_update(UIUpdate.new(:render, {})) if snapshot_refresh_required?(routed_event, refresh_snapshot)
    end

    def log_input_event(event)
      logger.debug("handle_event: #{event.type}")
      logger.debug("handle_event: focus: #{@focus}")
    end

    def snapshot_refresh_required?(event, refresh_snapshot)
      windows.length > 1 || (refresh_snapshot && SNAPSHOT_REFRESH_EVENTS.include?(event&.type) && !@stop_requested)
    end

    def activate_target_window(event)
      target = windows.find { |window| window.object_id == event.payload[:window_id] }
      activate_window(target) if target && !target.equal?(current_window)
    end

    def prepare_input_context(event, window)
      @active_source_id = event.payload.fetch(:source_id, :default)
      @active_page_size = [event.payload[:page_size].to_i, 1].max if event.payload.key?(:page_size)
      @active_page_window_id = event.payload[:window_id] || window&.object_id if @active_page_size
    end

    def dispatch_routed_input(event)
      routed_event = route_input_event(event)
      preserve_yank = %i[yank yank_pop].include?(routed_event&.type) || @focus == :minibuffer
      @last_yank = nil if routed_event && !preserve_yank
      break_typing_undo_groups unless routed_event&.type == :insert_char
      return unless routed_event

      @command_handler.handle(routed_event)
      routed_event
    end

    def break_typing_undo_groups
      session.buffers.each(&:break_typing_undo_group)
    end
  end
end
