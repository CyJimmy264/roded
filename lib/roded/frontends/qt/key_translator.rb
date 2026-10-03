module Roded
  module Frontends
    # Converts Qt key event payloads into the editor's shared key notation.
    class QtKeyTranslator
      SHIFTABLE_SPECIAL_KEYS = %w[Tab Enter Left Right Up Down].freeze
      SPECIAL_KEYS = {
        ::Qt::Key_Escape => "Esc",
        ::Qt::Key_Return => "Enter",
        ::Qt::Key_Enter => "Enter",
        ::Qt::Key_Backspace => "Backspace",
        ::Qt::Key_Delete => "Delete",
        ::Qt::Key_Left => "Left",
        ::Qt::Key_Right => "Right",
        ::Qt::Key_Up => "Up",
        ::Qt::Key_Down => "Down",
        ::Qt::Key_Tab => "Tab",
        ::Qt::Key_Space => "SPC",
        ::Qt::Key_F7 => "F7"
      }.freeze

      def translate(payload)
        key = payload_value(payload, :key, :a).to_i
        modifiers = payload_value(payload, :modifiers, :b).to_i
        name = key_name(key, payload_value(payload, :text, :c), modifiers)
        return unless name

        modified_name(name, modifiers)
      end

      private

      def payload_value(payload, key, alias_key)
        payload[key] || payload[alias_key]
      end

      def key_name(key, text, modifiers)
        return SPECIAL_KEYS[key] if SPECIAL_KEYS.key?(key)
        return key.chr.downcase if modifiers.anybits?(::Qt::ControlModifier) && key.between?(::Qt::Key_A, ::Qt::Key_Z)

        return text.to_s unless text.to_s.empty?

        key.chr if key.between?(::Qt::Key_A, ::Qt::Key_Z)
      end

      def modified_name(name, modifiers)
        parts = []
        parts << "C" if modifiers.anybits?(::Qt::ControlModifier)
        parts << "M" if modifiers.anybits?(::Qt::AltModifier)
        parts << "s" if modifiers.anybits?(::Qt::MetaModifier)
        shifted_key = shifted_key?(name, modifiers)
        parts << "S" if modifiers.anybits?(::Qt::ShiftModifier) && shifted_key
        return name if parts.empty?

        "#{parts.join("-")}-#{name}"
      end

      def shifted_key?(name, modifiers)
        SHIFTABLE_SPECIAL_KEYS.include?(name) ||
          (modifiers.anybits?(::Qt::ControlModifier) && name.match?(/\A[a-z]\z/))
      end
    end
  end
end
