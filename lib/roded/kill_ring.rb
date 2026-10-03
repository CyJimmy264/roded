module Roded
  # Stores killed text and joins adjacent kill commands into the newest entry.
  class KillRing
    attr_reader :items

    def initialize
      @items = []
      @continuing_kill = false
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
      @items.first
    end
  end
end
