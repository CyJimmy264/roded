require_relative "ruby_syntax_tokenizer"
require_relative "line_syntax_tokenizer"

module Roded
  # Produces frontend-independent token spans for the built-in editor modes.
  class SyntaxHighlighter
    MODES = %i[plain ruby json yaml markdown].freeze
    COLORS = {
      comment: "#5b6268",
      string: "#98be65",
      keyword: "#c678dd",
      number: "#d19a66",
      symbol: "#56b6c2",
      heading: "#61afef",
      punctuation: "#abb2bf"
    }.freeze

    def initialize
      @cache = {}
      @ruby_tokenizer = RubySyntaxTokenizer.new
      @ruby_rows = ObjectSpace::WeakMap.new
      @line_tokenizer = LineSyntaxTokenizer.new
    end

    def mode_for(filename)
      case File.extname(filename.to_s).downcase
      when ".rb", ".rake", ".gemspec" then :ruby
      when ".json" then :json
      when ".yml", ".yaml" then :yaml
      when ".md", ".markdown" then :markdown
      else :plain
      end
    end

    def spans(mode, lines)
      return plain_spans(lines.length) if mode.to_sym == :plain
      return @line_tokenizer.spans(mode, immutable_lines(lines)) unless mode.to_sym == :ruby

      cached_spans(mode, lines)
    rescue StandardError
      Array(lines).map { [].freeze }.freeze
    end

    private

    def cached_spans(mode, lines)
      stable_lines = immutable_lines(lines)
      key = [mode.to_sym, stable_lines].freeze
      @cache.fetch(key) { cache_result(key, generate_ruby_spans(stable_lines)) }
    end

    def plain_spans(count)
      @plain_spans ||= {}
      @plain_spans.shift if @plain_spans.length >= 12 && !@plain_spans.key?(count)
      @plain_spans[count] ||= Array.new(count, [].freeze).freeze
    end

    def ruby_spans(lines, rows)
      @ruby_tokenizer.spans(lines, rows)
    end

    def generate_ruby_spans(lines)
      rows = lines.map { [] }
      ruby_spans(lines, rows)
      rows.each_with_index.map { |spans, row| immutable_ruby_row(lines[row], spans) }.freeze
    end

    def immutable_ruby_row(line, spans)
      cached = @ruby_rows[line]
      return cached if cached == spans

      @ruby_rows[line] = spans.each(&:freeze).freeze
    end

    def immutable_lines(lines)
      return lines if lines.is_a?(Array) && lines.frozen? && lines.all? { |line| line.is_a?(String) && line.frozen? }

      Array(lines).map { |line| line.to_s.dup.freeze }.freeze
    end

    def cache_result(key, result)
      @cache.shift if @cache.length >= 12
      @cache[key] = result
    end
  end
end
