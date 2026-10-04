require_relative "ruby_highlight_fingerprint"

module Roded
  # Keeps a temporary presentation while a revision-checked lexical result is pending.
  class RubyHighlightState
    attr_reader :tokens, :signatures, :revision, :job_id

    def initialize(revision, lines, tokens)
      @revision = revision
      @lines = lines
      @tokens = tokens
      @signatures = tokens.map { |row| RubyHighlightFingerprint.call(row) }.freeze
    end

    def prepare(revision, lines)
      first, suffix = common_lines(lines)
      changed = lines.length - first - suffix
      @tokens = remap(@tokens, first, suffix, changed, [].freeze)
      @signatures = remap(@signatures, first, suffix, changed, nil)
      @revision = revision
      @lines = lines
      @job_id = nil
      @tokens
    end

    def submitted(job_id)
      @job_id = job_id
    end

    def apply(job_id, changes, failed: false) # rubocop:disable Naming/PredicateMethod -- applies the lexical result
      return false unless @job_id == job_id

      failed ? clear_rows : update_rows(changes)
      @job_id = nil
      true
    end

    private

    def clear_rows
      @tokens = Array.new(@lines.length, [].freeze).freeze
      @signatures = Array.new(@lines.length, RubyHighlightFingerprint.call([])).freeze
    end

    def update_rows(changes)
      tokens = @tokens.dup
      signatures = @signatures.dup
      changes.each do |row, spans, signature|
        tokens[row] = spans
        signatures[row] = signature
      end
      @tokens = tokens.freeze
      @signatures = signatures.freeze
    end

    def common_lines(lines)
      first = 0
      limit = [@lines.length, lines.length].min
      first += 1 while first < limit && @lines[first] == lines[first]
      suffix = 0
      suffix += 1 while suffix < limit - first && @lines[-suffix - 1] == lines[-suffix - 1]
      [first, suffix]
    end

    def remap(values, first, suffix, changed, empty)
      (values.take(first) + Array.new(changed, empty) + (suffix.positive? ? values.last(suffix) : [])).freeze
    end
  end
end
