module Roded
  # Declarative routing tables for normalized buffer and minibuffer events.
  module CommandHandlerEventMaps
    CURSOR_ACTIONS = {
      move_down: %i[move_cursor_down move_cursor down],
      move_up: %i[move_cursor_up move_cursor up],
      move_left: %i[move_cursor_left move_cursor left],
      move_right: %i[move_cursor_right move_cursor right],
      move_word_forward: %i[move_cursor_word_forward render],
      move_word_backward: %i[move_cursor_word_backward render],
      document_start: %i[move_cursor_document_start render],
      document_end: %i[move_cursor_document_end render],
      page_down: %i[move_cursor_page_down render page_size],
      page_up: %i[move_cursor_page_up render page_size],
      line_start: %i[move_cursor_line_start render],
      line_end: %i[move_cursor_line_end render]
    }.freeze

    SCROLL_EVENTS = %i[scroll_line_up scroll_line_down scroll_page_up scroll_page_down].freeze
    BUFFER_OPERATIONS = {
      kill_line: %i[kill_line kill_ring],
      backspace: [:backspace],
      delete: [:delete_char],
      enter: [:newline],
      insert_char: %i[insert_char char],
      paste: %i[insert_text text]
    }.freeze

    EDITOR_ACTIONS = {
      set_mark: [:set_mark],
      kill_region: [:kill_region],
      copy_region: [:copy_region],
      yank: [:yank],
      ruby_repl: [:open_ruby_repl],
      repl_evaluate: [:evaluate_ruby_repl],
      repl_interrupt: [:interrupt_ruby_repl],
      repl_history_previous: [:cycle_ruby_repl_history, -1],
      repl_history_next: [:cycle_ruby_repl_history, 1],
      shrink_window_horizontally: [:resize_window, -0.05],
      enlarge_window_horizontally: [:resize_window, 0.05],
      split_horizontal: %i[split_window horizontal],
      split_vertical: %i[split_window vertical],
      other_window: [:other_window],
      delete_window: [:delete_window],
      delete_other_windows: [:delete_other_windows],
      indent: [:indent],
      describe_bindings: [:describe_bindings]
    }.freeze

    COMMANDS = {
      save_buffer: "save",
      save_as_buffer: "save-as",
      open_file: "open",
      switch_buffer: "switch-buffer",
      previous_buffer: "previous-buffer",
      next_buffer: "next-buffer",
      kill_buffer: "kill-buffer",
      undo: "undo",
      redo: "redo",
      quit: "quit",
      request_quit: "quit"
    }.freeze

    PROMPTS = {
      yank_pop: [:kill_ring, "M-y "],
      line_search: [:line_search, "Find line: "],
      goto_line: [:goto_line, "Goto line: "],
      project_files: [:open, "Project file: "],
      start_command: [:command, "M-x "]
    }.freeze

    PICKER_MOVEMENTS = {
      move_down: [:move_picker, 1],
      move_up: [:move_picker, -1],
      scroll_line_up: [:move_picker_history, -1],
      scroll_line_down: [:move_picker_history, 1]
    }.freeze

    MINIBUFFER_MOVEMENTS = {
      move_left: :move_left,
      move_right: :move_right,
      line_start: :move_to_start,
      line_end: :move_to_end,
      page_up: :move_to_start,
      page_down: :move_to_end
    }.freeze

    MINIBUFFER_EDITS = {
      backspace: [:backspace],
      delete: [:delete_char],
      insert_char: %i[insert_char char]
    }.freeze

    BUFFER_EVENT_ROUTES = {}
                          .merge(CURSOR_ACTIONS.keys.to_h { |type| [type, :move_buffer_cursor] })
                          .merge(SCROLL_EVENTS.to_h { |type| [type, :scroll_viewport] })
                          .merge(BUFFER_OPERATIONS.keys.to_h { |type| [type, :operate_on_buffer] })
                          .merge(EDITOR_ACTIONS.keys.to_h { |type| [type, :call_editor_action] })
                          .merge(PROMPTS.keys.to_h { |type| [type, :start_prompt] })
                          .merge(COMMANDS.keys.to_h { |type| [type, :execute_registered_command] })
                          .merge(
                            query_replace: :begin_query_replace,
                            custom_command: :execute_custom_command,
                            scroll_by: :scroll_by,
                            render: :render_event,
                            cancel: :render_event,
                            noop: :ignore_event
                          ).freeze
  end
end
