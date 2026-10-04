module Roded
  module Frontends
    # Adds a visible block at end-of-line without covering the final character.
    module QtEolCaretRenderer
      STYLE = "color: #282c34; background-color: #61afef;".freeze

      def self.render(point, row, line_length)
        return "" unless point && point[:row] == row && point[:col] >= line_length

        "<span style=\"#{STYLE}\">&nbsp;</span>"
      end
    end
  end
end
