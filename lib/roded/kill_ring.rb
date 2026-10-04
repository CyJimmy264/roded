module Roded
  # Stores killed text and joins adjacent kill commands into the newest entry.
  class KillRing
    def initialize
      @items = []
      @continuing_kill = false
    end

    def items
      @items.map { |item| item.dup.freeze }.freeze
    end

    def push(text)
      return if text.nil? || text.empty?

      if @continuing_kill && @items.any?
        @items[0] += text
      else
        @items.unshift(text)
      end
      @continuing_kill = true
    end

    def break_sequence
      @continuing_kill = false
    end

    def last
      @items.first&.dup&.freeze
    end
  end
end
