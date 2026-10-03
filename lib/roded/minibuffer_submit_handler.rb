module Roded
  # Dispatches completed minibuffer submissions to editor actions.
  class MinibufferSubmitHandler
    HANDLERS = {
      command: ->(app, value) { app.process_command(value) },
      open: ->(app, value) { app.open_file(value) unless value.to_s.empty? },
      save: ->(app, value) { app.save_file(value) unless value.to_s.empty? },
      save_as: ->(app, value) { app.save_file(value) unless value.to_s.empty? },
      switch_buffer: ->(app, value) { app.switch_buffer(value) unless value.to_s.empty? },
      kill_buffer: ->(app, _value) { app.kill_current_buffer },
      close_confirmation: ->(app, value) { app.handle_close_prompt(:close_confirmation, value) },
      close_save_as: ->(app, value) { app.handle_close_prompt(:close_save_as, value) },
      overwrite_confirmation: ->(app, value) { app.handle_overwrite_confirmation(value) }
    }.freeze

    def initialize(application)
      @application = application
    end

    def handle(kind, value)
      HANDLERS[kind]&.call(@application, value)
    end
  end
end
