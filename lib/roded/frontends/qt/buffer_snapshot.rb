module Roded
  module Frontends
    # Builds an immutable presentation snapshot for a single Qt pane.
    class QtBufferSnapshot
      def self.capture(buffer, point: { row: 0, col: 0 })
        point = point.dup.freeze
        name = buffer.filename || buffer.name || "*scratch*"
        {
          text: buffer.to_s.dup.freeze,
          row: point.fetch(:row),
          col: point.fetch(:col),
          modeline: "-- Roded -- #{name}  #{point.fetch(:row) + 1}:#{point.fetch(:col) + 1}"
        }.freeze
      end
    end
  end
end
