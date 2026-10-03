module Roded
  # Query and selection state shared by interactive candidate lists.
  class Picker
    attr_reader :query, :selected_index, :candidates

    def initialize(candidates)
      @source = Array(candidates).map { |candidate| candidate.to_s.dup.freeze }.freeze
      @query = ""
      @selected_index = 0
      @moved = false
      refresh
    end

    def update_query(value)
      @query = value.to_s.dup
      @selected_index = 0
      @moved = false
      refresh
    end

    def move(amount)
      return if candidates.empty?

      @selected_index = (selected_index + amount.to_i) % candidates.length
      @moved = true
    end

    def selected
      return if query.empty? && !@moved

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
