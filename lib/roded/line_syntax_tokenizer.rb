module Roded
  # Reuses per-line spans for modes without cross-line lexical state.
  class LineSyntaxTokenizer
    MAX_CACHED_ROWS = 16_384

    def initialize
      @rows = {}
      @identities = {}
      @documents = {}
    end

    def spans(mode, lines)
      mode = mode.to_sym
      documents = (@documents[mode] ||= ObjectSpace::WeakMap.new)
      return documents[lines] if documents.key?(lines)

      documents[lines] = line_spans(mode, lines)
    end

    private

    def line_spans(mode, lines)
      cache = (@rows[mode] ||= {})
      identities = (@identities[mode] ||= ObjectSpace::WeakMap.new)
      lines.map { |line| cached_row(identities, cache, mode, line) }.freeze
    end

    def cached_row(identities, cache, mode, line)
      identities[line] ||= cache.fetch(line) { cache_line(cache, mode, line) }
    end

    def cache_line(cache, mode, line)
      cache.shift if cache.length >= MAX_CACHED_ROWS
      cache[line] = tokenize_line(mode, line)
    end

    def tokenize_line(mode, line)
      rows = [[]]
      handler = { json: :json_spans, yaml: :yaml_spans, markdown: :markdown_spans }[mode.to_sym]
      send(handler, [line], rows) if handler
      rows.first.map(&:freeze).freeze
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
