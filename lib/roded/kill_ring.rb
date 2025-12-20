module Roded
  class KillRing
    attr_reader :items

    def initialize
      @items = []
    end

    def push(text)
      return if text.nil? || text.empty?

      @items.unshift(text)
    end

    def last
      @items.first
    end
  end
end
