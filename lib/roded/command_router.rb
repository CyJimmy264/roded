module Roded
  # Resolves normalized key sequences through the active keymap.
  class CommandRouter
    def initialize(keymap)
      @keymap = keymap
      @pending_prefixes = {}
    end

    def route(key, source_id: nil, view_id: nil)
      return if key.nil?

      command = route_from_state(key, source_id || :default)
      command&.with(source_id:, view_id:)
    end

    private

    def route_from_state(key, stream_id)
      pending = @pending_prefixes[stream_id]
      return route_pending(pending, key, stream_id) if pending
      return start_prefix(key, stream_id) if prefix_key?(key)

      resolve(key) || insert_character(key) || editor_command(:noop, {})
    end

    def route_pending(pending, key, source_id)
      @pending_prefixes.delete(source_id)
      combined = pending.first == "Esc" ? "M-#{key}" : (pending + [key]).join(" ")
      mapped = resolve(combined)
      return mapped if mapped

      if @keymap&.prefix?(combined)
        @pending_prefixes[source_id] = pending.first == "Esc" ? [combined] : pending + [key]
        return editor_command(:prefix_pending, { prefix: combined })
      end

      editor_command(:noop, { invalid_sequence: combined })
    end

    def resolve(key)
      mapping = @keymap&.resolve(key)
      return unless mapping

      editor_command(mapping[:type], mapping[:payload] || {})
    end

    def insertable?(key)
      key.is_a?(String) && key.length == 1
    end

    def prefix_key?(key)
      key == "Esc" || @keymap&.prefix?(key)
    end

    def start_prefix(key, source_id)
      @pending_prefixes[source_id] = [key]
      editor_command(:prefix_pending, { prefix: key })
    end

    def insert_character(key)
      editor_command(:insert_char, { char: key }) if insertable?(key)
    end

    def editor_command(type, payload)
      EditorCommand.new(type, payload, nil, nil)
    end
  end
end
