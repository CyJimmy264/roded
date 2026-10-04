require "unicode/display_width"

module Roded
  module Frontends
    # Converts core character offsets to terminal display-cell geometry.
    class CursesTextGeometry
      TAB_WIDTH = 2
      REGIONAL_INDICATOR = (0x1F1E6..0x1F1FF)
      EMOJI_MODIFIER = (0x1F3FB..0x1F3FF)
      PRINTABLE_ASCII = /\A[\x20-\x7e]*\z/

      def self.width(text, initial_column: 0)
        column(text, text.to_s.length, initial_column:)
      end

      def self.column(text, character_offset, initial_column: 0)
        return [text.to_s.length, character_offset.to_i].min if PRINTABLE_ASCII.match?(text.to_s)

        text.to_s[0, character_offset.to_i].each_grapheme_cluster.reduce(0) do |occupied, cluster|
          occupied + cluster_width(cluster, initial_column + occupied)
        end
      end

      def self.clip(text, cell_limit, initial_column: 0)
        limit = [cell_limit.to_i, 0].max
        return text.to_s[0, limit] if PRINTABLE_ASCII.match?(text.to_s)

        clip_graphemes(text.to_s, limit, initial_column)
      end

      def self.clip_graphemes(text, limit, initial_column)
        output = +""
        occupied = 0
        text.to_s.each_grapheme_cluster do |cluster|
          cells = cluster_width(cluster, initial_column + occupied)
          break if occupied + cells > limit

          output << (cluster == "\t" ? " " * cells : cluster)
          occupied += cells
        end
        output
      end

      def self.horizontal_origin(text, point, origin, cell_limit)
        line = text.to_s
        offset = [origin.to_i, 0].max
        return [point.to_i, 0].max if point.to_i < offset

        return offset unless cell_limit.positive?
        return [offset, [point.to_i, line.length].min - cell_limit + 1].max if PRINTABLE_ASCII.match?(line)

        cluster_origin(line, point, offset, cell_limit)
      end

      def self.cluster_origin(line, point, origin, limit)
        target = column(line, point)
        offset = 0
        occupied = 0
        line.each_grapheme_cluster do |cluster|
          return offset if offset >= origin && target - occupied < limit
          return legacy_origin(line, point, origin, limit) if offset < origin && offset + cluster.length > origin

          occupied += cluster_width(cluster, occupied)
          offset += cluster.length
        end
        offset
      end

      def self.legacy_origin(line, point, offset, cell_limit)
        target = column(line, point)
        while target - column(line, offset) >= cell_limit
          cluster = line[offset..].to_s.each_grapheme_cluster.first
          break unless cluster

          offset += cluster.length
        end
        offset
      end

      def self.cluster_width(cluster, column = 0)
        return TAB_WIDTH - (column % TAB_WIDTH) if cluster == "\t"

        codepoints = cluster.codepoints
        regional_count = codepoints.count { |codepoint| REGIONAL_INDICATOR.cover?(codepoint) }
        return 2 if emoji_cluster?(cluster, codepoints, regional_count)

        Unicode::DisplayWidth.of(cluster)
      end

      def self.emoji_cluster?(cluster, codepoints, regional_count)
        cluster.include?("\u200d") || regional_count >= 2 ||
          codepoints.any? { |codepoint| EMOJI_MODIFIER.cover?(codepoint) }
      end
      private_class_method :cluster_width, :emoji_cluster?, :cluster_origin, :legacy_origin, :clip_graphemes
    end
  end
end
