require "prism"
require "ripper"
require_relative "ruby_token_position"

module Roded
  # Uses Prism's native tokens without constructing Ripper-compatible state wrappers.
  class RubySyntaxTokens
    EVENTS = {
      COMMENT: :on_comment, EMBDOC_LINE: :on_embdoc,
      STRING_BEGIN: :on_tstring_beg, STRING_CONTENT: :on_tstring_content, STRING_END: :on_tstring_end,
      REGEXP_BEGIN: :on_regexp_beg, REGEXP_END: :on_regexp_end,
      SYMBOL_BEGIN: :on_symbeg, LABEL: :on_label
    }.freeze

    def initialize
      @events = EVENTS.dup
    end

    def each(source, &block)
      result = Prism.lex(source)
      # Squiggly heredocs need Ripper's dedented positions and ignored whitespace.
      if result.value.any? { |entry| entry.first.type == :HEREDOC_START }
        Ripper.lex(source).each { |token| block.call(*token) }
      else
        native_tokens(result, &block)
      end
    end

    private

    def native_tokens(result)
      positions = RubyTokenPosition.new(result.source.offsets)
      result.value.each do |entry|
        token = entry.first
        event = token_event(token.type)
        next unless event

        yield positions.position(token.location), event, token.value
      end
    end

    def token_event(type)
      @events.fetch(type) { @events[type] = event_for(type) }
    end

    def event_for(type)
      name = type.to_s
      return :on_kw if name.start_with?("KEYWORD_")
      return :on_int if name.start_with?("INTEGER")
      return :on_float if name.start_with?("FLOAT")

      nil
    end
  end
end
