module Roded
  # Resolves normalized key sequences through the active keymap.
  class CommandRouter
    def initialize(keymap)
      @keymap = keymap
      @pending_prefixes = {}
    end

    def route(key, source_id: :default)
      return if key.nil?

      pending = @pending_prefixes[source_id]
      return route_pending(pending, key, source_id) if pending
      return start_prefix(key, source_id) if prefix_key?(key)

      resolve(key) || insert_character(key) || Event.new(:noop, {})
    end

    private

    def route_pending(pending, key, source_id)
      @pending_prefixes.delete(source_id)
      combined = pending.first == "Esc" ? "M-#{key}" : (pending + [key]).join(" ")
      mapped = resolve(combined)
      return mapped if mapped

      if @keymap&.prefix?(combined)
        @pending_prefixes[source_id] = pending.first == "Esc" ? [combined] : pending + [key]
        return Event.new(:prefix_pending, { prefix: combined })
      end

      Event.new(:noop, { invalid_sequence: combined })
    end

    def resolve(key)
      mapping = @keymap&.resolve(key)
      return unless mapping

      Event.new(mapping[:type], mapping[:payload])
    end

    def insertable?(key)
      key.is_a?(String) && key.length == 1
    end

    def prefix_key?(key)
      key == "Esc" || @keymap&.prefix?(key)
    end

    def start_prefix(key, source_id)
      @pending_prefixes[source_id] = [key]
      Event.new(:prefix_pending, { prefix: key })
    end

    def insert_character(key)
      Event.new(:insert_char, { char: key }) if insertable?(key)
    end
  end
end
