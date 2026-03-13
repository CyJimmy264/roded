module Roded
  class CommandRouter
    def initialize(keymap)
      @keymap = keymap
      @pending_prefix = nil
    end

    def route(key)
      return if key.nil?

      if @pending_prefix
        prefix = @pending_prefix
        @pending_prefix = nil
        combined = prefix == "M" ? "M-#{key}" : "#{prefix} #{key}"
        mapped = resolve(combined)
        return mapped if mapped
      end

      if key == "C-x"
        @pending_prefix = "C-x"
        return Event.new(:noop, {})
      end

      if key == "Esc"
        @pending_prefix = "M"
        return Event.new(:noop, {})
      end

      mapped = resolve(key)
      return mapped if mapped

      return Event.new(:insert_char, { char: key }) if insertable?(key)

      Event.new(:noop, {})
    end

    private

    def resolve(key)
      mapping = @keymap&.resolve(key)
      return unless mapping

      Event.new(mapping[:type], mapping[:payload])
    end

    def insertable?(key)
      key.is_a?(String) && key.length == 1
    end
  end
end
