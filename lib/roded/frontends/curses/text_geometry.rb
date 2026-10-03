require "unicode/display_width"

module Roded
  module Frontends
    # Converts core character offsets to terminal display-cell geometry.
    class CursesTextGeometry
      REGIONAL_INDICATOR = (0x1F1E6..0x1F1FF)
      EMOJI_MODIFIER = (0x1F3FB..0x1F3FF)

      def self.width(text)
        text.to_s.each_grapheme_cluster.sum { |cluster| cluster_width(cluster) }
      end

      def self.column(text, character_offset)
        width(text.to_s[0, character_offset.to_i])
      end

      def self.clip(text, cell_limit)
        limit = [cell_limit.to_i, 0].max
        output = +""
        occupied = 0
        text.to_s.each_grapheme_cluster do |cluster|
          cells = cluster_width(cluster)
          break if occupied + cells > limit

          output << cluster
          occupied += cells
        end
        output
      end

      def self.horizontal_origin(text, point, origin, cell_limit)
        line = text.to_s
        offset = [origin.to_i, 0].max
        return [point.to_i, 0].max if point.to_i < offset

        while cell_limit.positive? && width(line[offset...point.to_i]) >= cell_limit
          cluster = line[offset..].to_s.each_grapheme_cluster.first
          break unless cluster

          offset += cluster.length
        end
        offset
      end

      def self.cluster_width(cluster)
        codepoints = cluster.codepoints
        regional_count = codepoints.count { |codepoint| REGIONAL_INDICATOR.cover?(codepoint) }
        return 2 if emoji_cluster?(cluster, codepoints, regional_count)

        Unicode::DisplayWidth.of(cluster)
      end

      def self.emoji_cluster?(cluster, codepoints, regional_count)
        cluster.include?("\u200d") || regional_count >= 2 ||
          codepoints.any? { |codepoint| EMOJI_MODIFIER.cover?(codepoint) }
      end
      private_class_method :cluster_width, :emoji_cluster?
    end
  end
end
