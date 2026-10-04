require_relative "syntax_highlighter"
require_relative "ruby_highlight_fingerprint"

module Roded
  # The lexer runs in a separate interpreter, outside the editor's Ruby GVL.
  class RubyHighlightServer
    def initialize(input, output)
      @input = input
      @output = output
      @highlighter = SyntaxHighlighter.new
    end

    def run
      loop do
        job = Marshal.load(@input) # rubocop:disable Security/MarshalLoad -- private pipe from this editor process
        lines = job.fetch(:lines).each(&:freeze).freeze
        tokens = @highlighter.spans(:ruby, lines)
        changed_rows(tokens, job.fetch(:signatures)).each_slice(32) { |batch| Marshal.dump(batch, @output) }
        Marshal.dump(nil, @output)
        @output.flush
      end
    rescue EOFError
      nil
    end

    private

    def changed_rows(tokens, signatures)
      tokens.each_with_index.filter_map do |spans, row|
        signature = RubyHighlightFingerprint.call(spans)
        [row, spans, signature] unless signatures[row] == signature
      end
    end
  end
end

Roded::RubyHighlightServer.new($stdin.binmode, $stdout.binmode).run if $PROGRAM_NAME == __FILE__
