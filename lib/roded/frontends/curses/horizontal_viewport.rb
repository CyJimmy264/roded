module Roded
  module Frontends
    # Retains the displayed origin until the caret crosses a viewport edge.
    class CursesHorizontalViewport
      def initialize
        @windows = {}
      end

      def origin(item, width)
        previous = @windows[item[:id]]
        requested = item[:left_column].to_i
        left = same_view?(previous, item, requested) ? previous[:left] : requested
        left = adjusted_origin(item, left, width)
        @windows[item[:id]] = { buffer: buffer_identity(item), requested:, left: }
        left
      end

      def retain(windows)
        ids = windows.map { |item| item[:id] }
        @windows.select! { |id, _state| ids.include?(id) }
      end

      private

      def adjusted_origin(item, left, width)
        point = item[:point]
        CursesTextGeometry.horizontal_origin(item[:lines][point[:row]].to_s, point[:col], left, width)
      end

      def same_view?(previous, item, requested)
        previous && previous[:buffer] == buffer_identity(item) && previous[:requested] == requested
      end

      def buffer_identity(item) = item[:buffer_id] || item[:name]
    end
  end
end
