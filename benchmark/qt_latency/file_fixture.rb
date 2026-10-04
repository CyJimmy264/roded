require_relative "../roded/fixture"

module Roded
  module Benchmarking
    # Reproduces an actual document without writing to it; snapshots retain content hashes.
    class LatencyFileFixture
      attr_reader :text, :line_count, :profile, :mode, :filename

      def initialize(path)
        @filename = File.expand_path(path)
        @text = File.read(filename, encoding: Encoding::UTF_8).freeze
        @line_count = [text.split("\n", -1).length, 1].max
        @mode = SyntaxHighlighter.new.mode_for(filename)
        @profile = mode.to_s
      end

      def metadata
        { filename:, lines: line_count, profile:, bytes: text.bytesize,
          sha256: Digest::SHA256.hexdigest(text) }
      end

      def self.build(config)
        return new(config[:file]) if config[:file]

        Fixture.new(line_count: config.fetch(:lines), profile: config.fetch(:profile),
                    line_length: config[:line_length])
      end
    end
  end
end
