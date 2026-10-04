require "digest"

module Roded
  module Benchmarking
    # Versioned, deterministic documents with long lines and optional Unicode/syntax.
    class Fixture
      VERSION = 1
      PROFILES = %w[plain ruby unicode].freeze

      attr_reader :line_count, :profile, :text, :block

      def initialize(line_count:, profile:, line_length: nil)
        @line_count = line_count
        @profile = profile
        @line_length = line_length
        @text = Array.new(line_count) { |index| padded_line(index) }.join("\n").freeze
        @block = Array.new(100) { |index| "inserted block line #{index}" }.join("\n").freeze
      end

      def metadata
        { version: VERSION, lines: line_count, profile:, bytes: text.bytesize,
          sha256: Digest::SHA256.hexdigest(text), block_lines: 100 }
      end

      def mode = profile == "ruby" ? :ruby : :plain

      private

      def padded_line(index)
        content = line(index)
        return content unless @line_length && content.length < @line_length

        padding = profile == "unicode" ? " длинная_строка" : " long_column"
        content + (padding * (@line_length - content.length).fdiv(padding.length).ceil)
      end

      def line(index)
        prefix = format("row_%06d", index)
        case profile
        when "plain" then "#{prefix} alpha beta gamma delta #{"long_column " * 24}end"
        when "ruby" then "#{prefix} = { count: #{index}, label: \"#{"long string " * 24}\" } # comment"
        when "unicode" then "#{prefix}\tстрока 界 🙂 e\u0301 #{"длинная строка " * 24}конец"
        else raise ArgumentError, "unknown fixture profile: #{profile}"
        end
      end
    end
  end
end
