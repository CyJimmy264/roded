module Roded
  # Fits a picker snapshot into a frontend's available row count.
  class PickerViewport
    def self.slice(candidates, selected_index, limit:)
      rows = Array(candidates)
      count = [limit.to_i, rows.length].min
      return { candidates: [].freeze, selected_index: 0 }.freeze unless count.positive?

      window_for(rows, selected_index, count)
    end

    def self.window_for(rows, selected_index, count)
      selected = selected_index.to_i.clamp(0, rows.length - 1)
      start = start_index(selected, count, rows.length)
      {
        candidates: rows.slice(start, count).to_a.freeze,
        selected_index: selected - start
      }.freeze
    end
    private_class_method :window_for

    def self.start_index(selected, count, length)
      [selected - (count / 2), 0].max.clamp(0, [length - count, 0].max)
    end
    private_class_method :start_index
  end
end
