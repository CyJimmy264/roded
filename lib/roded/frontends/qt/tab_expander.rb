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
        fragment = @line[first...last].to_s
        return fragment unless fragment.include?("\t")

        visual_column = display_width(@line[0...first].to_s)
        expand_parts(fragment.split("\t", -1), visual_column)
      end

      private

      def expand_parts(parts, visual_column)
        parts.each_with_index.with_object(+"") do |(part, index), expanded|
          expanded << part
          next if index == parts.length - 1

          visual_column += display_width(part)
          visual_column += append_tab(expanded, visual_column)
        end
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
