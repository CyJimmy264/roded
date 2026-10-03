require "unicode/display_width"

module Roded
  module Frontends
    # Expands core tabs to the Qt pane's two-cell display stops.
    class QtTabExpander
      TAB_WIDTH = 2

      def self.expand(line, first, last)
        new(line).expand(first, last)
      end

      def initialize(line)
        @line = line
      end

      def expand(first, last)
        visual_column = display_width(@line[0...first].to_s)
        @line[first...last].to_s.each_grapheme_cluster.with_object(+"") do |cluster, expanded|
          visual_column += append_cluster(expanded, cluster, visual_column)
        end
      end

      private

      def append_cluster(expanded, cluster, visual_column)
        return append_tab(expanded, visual_column) if cluster == "\t"

        expanded << cluster
        Unicode::DisplayWidth.of(cluster)
      end

      def append_tab(expanded, visual_column)
        spaces = TAB_WIDTH - (visual_column % TAB_WIDTH)
        expanded << (" " * spaces)
        spaces
      end

      def display_width(text)
        text.each_grapheme_cluster.reduce(0) do |column, cluster|
          column + (cluster == "\t" ? TAB_WIDTH - (column % TAB_WIDTH) : Unicode::DisplayWidth.of(cluster))
        end
      end
    end
  end
end
