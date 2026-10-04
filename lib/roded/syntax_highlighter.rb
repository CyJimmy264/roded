require_relative "ruby_syntax_tokenizer"

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

      cached_spans(mode, lines)
    rescue StandardError
      Array(lines).map { [].freeze }.freeze
    end

    private

    def cached_spans(mode, lines)
      stable_lines = Array(lines).map { |line| line.to_s.dup.freeze }.freeze
      key = [mode.to_sym, stable_lines].freeze
      @cache.fetch(key) { cache_result(key, generate_spans(mode, stable_lines)) }
    end

    def plain_spans(count)
      @plain_spans ||= {}
      @plain_spans.shift if @plain_spans.length >= 12 && !@plain_spans.key?(count)
      @plain_spans[count] ||= Array.new(count, [].freeze).freeze
    end

    def ruby_spans(lines, rows)
      @ruby_tokenizer.spans(lines, rows)
    end

    def generate_spans(mode, lines)
      rows = lines.map { [] }
      tokenizer = tokenizers[mode.to_sym]
      tokenizer&.call(lines, rows)
      rows.map { |spans| spans.map(&:freeze).freeze }.freeze
    end

    def cache_result(key, result)
      @cache.shift if @cache.length >= 12
      @cache[key] = result
    end

    def tokenizers
      {
        ruby: method(:ruby_spans),
        json: method(:json_spans),
        yaml: method(:yaml_spans),
        markdown: method(:markdown_spans)
      }
    end

    def json_spans(lines, rows)
      Array(lines).each_with_index do |line, row|
        add_matches(rows, row, line, /"(?:\\.|[^"\\])*"/, :string)
        add_matches(rows, row, line, /\b(?:true|false|null)\b/, :keyword)
        add_matches(rows, row, line, /-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b/, :number)
      end
    end

    def yaml_spans(lines, rows)
      Array(lines).each_with_index do |line, row|
        add_match(rows, row, line, /#.*\z/, :comment)
        add_match(rows, row, line, /\A\s*(?:-\s*)?[^:#][^:]*:/, :symbol)
        add_matches(rows, row, line, /(?:"(?:\\.|[^"\\])*"|'[^']*')/, :string)
        add_matches(rows, row, line, /\b(?:true|false|null|yes|no)\b/i, :keyword)
        add_matches(rows, row, line, /\b\d+(?:\.\d+)?\b/, :number)
      end
    end

    def markdown_spans(lines, rows)
      Array(lines).each_with_index do |line, row|
        add_match(rows, row, line, /\A\s*\#{1,6}\s+.*\z/, :heading)
        add_matches(rows, row, line, /`[^`]+`/, :string)
        add_matches(rows, row, line, /\*\*[^*]+\*\*/, :keyword)
        add_matches(rows, row, line, /\[[^\]]+\]\([^)]+\)/, :symbol)
      end
    end

    def add_match(rows, row, line, pattern, category)
      match = pattern.match(line)
      add_span(rows, row, match.begin(0), match[0], category) if match
    end

    def add_matches(rows, row, line, pattern, category)
      line.to_enum(:scan, pattern).each do
        match = Regexp.last_match
        add_span(rows, row, match.begin(0), match[0], category)
      end
    end

    def add_span(rows, row, start, text, category)
      rows[row] << { start:, finish: start + text.length, category: }
    end
  end
end
