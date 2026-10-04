module Roded
  # Query and selection state shared by interactive candidate lists.
  class Picker
    attr_reader :query, :selected_index, :candidates, :history

    def initialize(candidates, history: [])
      @source = Array(candidates).map { |candidate| candidate.to_s.dup.freeze }.freeze
      @history = Array(history).map { |query| query.to_s.dup.freeze }.freeze
      @query = ""
      @selected_index = 0
      @moved = false
      @history_index = nil
      @history_draft = nil
      refresh
    end

    def update_query(value)
      @history_index = nil
      @history_draft = nil
      replace_query(value)
    end

    def move_history(amount)
      return if history.empty?

      if amount.to_i.negative?
        move_history_previous
      else
        move_history_next
      end
      query
    end

    def commit_query
      return history if query.empty? || history.last == query

      @history = (history + [query.dup.freeze]).freeze
      @history_index = nil
      @history_draft = nil
      history
    end

    def move(amount)
      return if candidates.empty?

      @selected_index = (selected_index + amount.to_i) % candidates.length
      @moved = true
    end

    def selected
      candidates[selected_index]
    end

    def snapshot(limit: 8)
      start = candidate_window_start(limit)
      {
        query: query.dup.freeze,
        selected_index: selected_index - start,
        candidates: candidates.slice(start, limit).to_a.freeze
      }.freeze
    end

    private

    def move_history_previous
      @history_draft = query.dup if @history_index.nil?
      @history_index = [(@history_index || history.length) - 1, 0].max
      replace_query(history.fetch(@history_index))
    end

    def move_history_next
      return if @history_index.nil?

      if @history_index >= history.length - 1
        @history_index = nil
        draft = @history_draft || ""
        @history_draft = nil
        replace_query(draft)
      else
        @history_index += 1
        replace_query(history.fetch(@history_index))
      end
    end

    def replace_query(value)
      @query = value.to_s.dup
      @selected_index = 0
      @moved = false
      refresh
    end

    def refresh
      terms = query.downcase.split
      @candidates = @source.select do |candidate|
        folded = candidate.downcase
        terms.all? { |term| folded.include?(term) }
      end.freeze
      @selected_index = 0 if candidates.empty?
      @selected_index = [selected_index, candidates.length - 1].min
    end

    def candidate_window_start(limit)
      centered = [selected_index - (limit / 2), 0].max
      centered.clamp(0, [candidates.length - limit, 0].max)
    end
  end
end
