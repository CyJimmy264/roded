require "digest"

module Roded
  # Stable across processes; permits sending only rows whose lexical spans changed.
  module RubyHighlightFingerprint
    def self.call(spans)
      Digest::SHA256.digest(Marshal.dump(spans)).freeze
    end
  end
end
