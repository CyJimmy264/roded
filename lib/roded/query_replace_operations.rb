module Roded
  # Implements interactive search, skip, replace-all, and cancel behavior.
  module QueryReplaceOperations
    def begin_query_replace
      @query_replace_state = { start: current_window.point.dup }
      start_minibuffer(:query_replace_search, "Query replace: ")
    end

    def accept_query_replace_search(query)
      return finish_query_replace if query.to_s.empty?

      @query_replace_state[:query] = query.to_s
      start_minibuffer(:query_replace_replacement, "Replace with: ")
    end

    def accept_query_replace_replacement(replacement)
      @query_replace_state[:replacement] = replacement.to_s
      advance_query_replace
    end

    def confirm_query_replace(answer)
      action = confirmation_action(answer)
      return start_minibuffer(:query_replace_confirm, confirmation_prompt) unless action
      return finish_readonly_query_replace if current_buffer.readonly && %w[y !].include?(answer.to_s.downcase)

      action.call
    end

    def cancel_query_replace
      start = @query_replace_state&.fetch(:start)
      @query_replace_state = nil
      current_window.highlight = nil
      move_to_position(start[:row], start[:col]) if start
    end

    private

    def confirmation_action(answer)
      {
        "y" => -> { replace_and_continue },
        "n" => -> { skip_and_continue },
        "!" => -> { replace_all_query_matches },
        "q" => -> { finish_query_replace }
      }[answer.to_s.downcase]
    end

    def confirmation_prompt
      "Replace? y, n, !, or q: "
    end

    def replace_and_continue
      replace_query_match
      advance_query_replace
    end

    def skip_and_continue
      move_to_position(*after_query_match)
      advance_query_replace
    end

    def advance_query_replace
      return start_minibuffer(:query_replace_confirm, confirmation_prompt) if query_replace_next

      finish_query_replace
    end

    def query_replace_next(position = current_window.point)
      state = @query_replace_state
      match = find_match(state.fetch(:query), :forward, from: position, inclusive: true)
      return nil unless match

      state[:position] = match
      query = state.fetch(:query)
      move_to_position(*match, highlight: match_range(match, query))
      match
    end

    def replace_query_match
      state = @query_replace_state
      first, last = query_match_boundaries(state)
      current_window.highlight = { start: first, finish: last }
      current_buffer.with_undo_group do
        current_buffer.delete_region(first, last)
        current_buffer.insert_text(state.fetch(:replacement), at: first)
      end
      state[:position] = current_window.point.values_at(:row, :col)
    end

    def query_match_boundaries(state)
      row, column = state.fetch(:position)
      [{ row:, col: column }, { row:, col: column + state.fetch(:query).length }]
    end

    def replace_all_query_matches
      current_buffer.with_undo_group do
        replace_query_match while query_replace_next
      end
      finish_query_replace
    end

    def after_query_match
      row, column = @query_replace_state.fetch(:position)
      [row, column + @query_replace_state.fetch(:query).length]
    end

    def finish_query_replace
      @query_replace_state = nil
      current_window.highlight = nil
      cancel_minibuffer if @focus == :minibuffer
      display_message("Query replace finished.")
    end

    def finish_readonly_query_replace
      cancel_query_replace
      cancel_minibuffer if @focus == :minibuffer
      display_message("Cannot replace text in a read-only buffer.")
    end
  end
end
