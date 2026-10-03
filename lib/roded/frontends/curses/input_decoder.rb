require "io/wait"

module Roded
  module Frontends
    # Normalizes terminal key sequences without depending on curses window state.
    class CursesKeyTranslator
      KEY_BINDINGS = {
        "[A".b => "Up", "OA".b => "Up", "[B".b => "Down", "OB".b => "Down",
        "[C".b => "Right", "OC".b => "Right", "[D".b => "Left", "OD".b => "Left",
        "[3~".b => "Delete"
      }.freeze
      SEQUENCES = KEY_BINDINGS.keys.freeze

      def timeout(sequence, paste_start)
        return 0.03 if sequence.empty?

        known_prefix = SEQUENCES.any? { |candidate| candidate.start_with?(sequence) } ||
                       paste_start.start_with?(sequence)
        known_prefix ? 0.25 : 0.03
      end

      def complete_sequence?(sequence, paste_start)
        SEQUENCES.include?(sequence) || sequence == paste_start
      end

      def translate_escape(sequence)
        return KEY_BINDINGS.fetch(sequence) if KEY_BINDINGS.key?(sequence)

        utf8 = sequence.dup.force_encoding("UTF-8")
        return "M-#{utf8}" if utf8.valid_encoding?
        return "M-#{normalize_input(sequence)}" if sequence.length == 1

        "Esc"
      end

      def expected_utf8_length(byte)
        return 1 if byte < 0x80
        return 2 if byte.between?(0xC0, 0xDF)
        return 3 if byte.between?(0xE0, 0xEF)
        return 4 if byte.between?(0xF0, 0xF7)

        nil
      end

      def normalize_input(text)
        return "Enter" if ["\n", "\r"].include?(text)
        return "Backspace" if text == "\u007F"

        codepoint = text.ord
        return "C-SPC" if codepoint.zero?
        return "C-#{(codepoint + 96).chr}" if codepoint.between?(1, 26)

        text
      end
    end

    # Turns terminal bytes, including bracketed paste, into editor input values.
    # Isolates terminal protocol state from drawing and window lifecycle.
    class CursesInputDecoder
      PasteInput = Data.define(:text)
      BRACKETED_PASTE_START = "[200~".b.freeze
      BRACKETED_PASTE_END = "\e[201~".b.freeze

      def initialize
        @input_buffer = +"".b
        @pending_input = +"".b
        @key_translator = CursesKeyTranslator.new
      end

      def read_key(stdin, wake_reader)
        return read_input_key(stdin, wake_reader) unless @pending_input.empty?

        readable, = IO.select([stdin, wake_reader])
        return nil unless readable
        return :quit_signal if readable.include?(wake_reader)

        read_input_key(stdin, wake_reader)
      rescue IO::WaitReadable
        decode_input_buffer
      end

      private

      def read_input_key(stdin, wake_reader)
        loop do
          ch = read_input_byte(stdin)
          return nil unless ch
          return read_escape_sequence(stdin, wake_reader) if ch == "\e"

          @input_buffer << ch
          key = decode_input_buffer
          return key if key
        end
      rescue IO::WaitReadable
        decode_input_buffer
      end

      def read_input_byte(stdin)
        return stdin.read_nonblock(1) if @pending_input.empty?

        byte = @pending_input.byteslice(0, 1)
        @pending_input = @pending_input.byteslice(1..) || +"".b
        byte
      end

      def read_escape_sequence(stdin, wake_reader)
        sequence = collect_escape_sequence(stdin)
        return "Esc" if sequence.empty?
        if paste_start?(sequence)
          return read_bracketed_paste(stdin, wake_reader, sequence.delete_prefix(BRACKETED_PASTE_START))
        end

        @key_translator.translate_escape(sequence)
      end

      def collect_escape_sequence(stdin)
        sequence = +"".b
        loop do
          break unless stdin.wait_readable(@key_translator.timeout(sequence, BRACKETED_PASTE_START))

          sequence << stdin.read_nonblock(1)
          break if @key_translator.complete_sequence?(sequence, BRACKETED_PASTE_START)
        end
        sequence
      end

      def paste_start?(sequence)
        sequence.start_with?(BRACKETED_PASTE_START)
      end

      def read_bracketed_paste(stdin, wake_reader, initial)
        content = initial.b
        loop do
          result = consume_paste_chunk(content, stdin, wake_reader)
          return result if result
        rescue EOFError
          return PasteInput.new(content.force_encoding("UTF-8"))
        end
      end

      def consume_paste_chunk(content, stdin, wake_reader)
        ending_index = content.index(BRACKETED_PASTE_END)
        return finish_bracketed_paste(content, ending_index) if ending_index

        chunk = read_paste_chunk(stdin, wake_reader)
        return :quit_signal if chunk == :quit_signal

        content << chunk
        nil
      end

      def finish_bracketed_paste(content, index)
        pasted = content.byteslice(0, index).force_encoding("UTF-8")
        ending_length = BRACKETED_PASTE_END.bytesize
        trailing = content.byteslice((index + ending_length)..)
        @pending_input = trailing + @pending_input if trailing && !trailing.empty?
        PasteInput.new(pasted)
      end

      def read_paste_chunk(stdin, wake_reader)
        readable, = IO.select([stdin, wake_reader])
        return :quit_signal if readable&.include?(wake_reader)
        return +"".b unless readable

        stdin.read_nonblock(4096)
      end

      def decode_input_buffer
        return nil if @input_buffer.empty?

        utf8 = @input_buffer.dup.force_encoding("UTF-8")
        if utf8.valid_encoding?
          @input_buffer.clear
          return @key_translator.normalize_input(utf8)
        end

        expected = @key_translator.expected_utf8_length(@input_buffer.getbyte(0))
        @input_buffer.clear if expected.nil? || @input_buffer.bytesize >= expected
        nil
      end
    end
  end
end
