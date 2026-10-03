module Roded
  # Applies REPL events and marshals editor API work onto the core thread.
  module RubyReplEventOperations
    private

    def handle_repl_api_event(event)
      payload = event.payload
      value = dispatch_repl_api(payload.fetch(:action), payload.fetch(:arguments))
      payload.fetch(:response) << [true, value]
    rescue StandardError => e
      payload.fetch(:response) << [false, e]
    end

    def dispatch_repl_api(action, arguments)
      case action
      when :snapshot, :buffers, :current_buffer, :windows, :repl_history then repl_snapshot_api(action)
      else dispatch_repl_mutation(action, arguments)
      end
    end

    def repl_snapshot_api(action)
      case action
      when :snapshot, :windows then editor_snapshot_for(action)
      when :buffers, :current_buffer then buffer_snapshots_for(action)
      when :repl_history then @ruby_repl_session&.history || [].freeze
      end
    end

    def editor_snapshot_for(action)
      action == :windows ? editor_snapshot.fetch(:windows) : editor_snapshot
    end

    def buffer_snapshots_for(action)
      return repl_buffer_snapshot(current_buffer) if action == :current_buffer

      buffers.map { |buffer| repl_buffer_snapshot(buffer) }.freeze
    end

    def dispatch_repl_mutation(action, arguments)
      case action
      when :insert_text then insert_repl_text(arguments.fetch(0))
      when :open_file then open_file(arguments.fetch(0))
      when :save_file then save_repl_file(arguments.fetch(0))
      when :switch_buffer then switch_buffer(arguments.fetch(0))
      when :execute_command then execute_command(arguments.fetch(0))
      when :register_command then register_repl_command(*arguments)
      else raise ArgumentError, "Unsupported editor API call: #{action}"
      end
    end

    def repl_buffer_snapshot(buffer)
      return unless buffer

      {
        name: buffer.name.to_s.dup.freeze,
        filename: buffer.filename&.dup&.freeze,
        text: buffer.to_s.dup.freeze,
        mode: buffer.mode,
        modified: buffer.modified?,
        readonly: buffer.readonly
      }.freeze
    end

    def insert_repl_text(text)
      current_buffer.insert_text(text.to_s)
      current_window.point = current_buffer.cursor_pos if current_window
      publish_ui_update(UIUpdate.new(:render, {}))
      current_buffer.to_s.dup.freeze
    end

    def save_repl_file(path)
      filename = path || current_buffer.filename
      raise ArgumentError, "Pass a path to save an unnamed buffer" unless filename

      save_file(filename)
    end

    def register_repl_command(name, binding, description, action)
      wrapped = action && ->(_application) { action.call(@ruby_editor_api) }
      register_command(name, binding:, description:, &wrapped)
    end

    def append_ruby_repl_result(payload)
      buffer = @ruby_repl_buffer
      return unless buffer

      append_repl_output(buffer, payload)
      @ruby_repl_session = nil if payload[:exit]
      @ruby_repl_input_start = payload[:exit] ? nil : buffer.cursor_pos
      @ruby_repl_history_index = nil
      @ruby_repl_history_draft = nil
      current_window.point = buffer.cursor_pos if current_buffer.equal?(buffer) && current_window
      publish_ui_update(UIUpdate.new(:render, {}))
    end

    def append_repl_output(buffer, payload)
      buffer.cursor_pos = { row: buffer.lines.length - 1, col: buffer.lines.last.length }
      buffer.insert_text(format_repl_output(payload))
    end

    def shutdown_ruby_repl
      @ruby_repl_session&.close
    end
  end
end
