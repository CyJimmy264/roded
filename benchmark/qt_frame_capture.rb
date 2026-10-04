require "fileutils"

module Roded
  module Benchmarking
    # Checks painted X11 pixels, rather than treating changed document data as a frame.
    class QtFrameCapture
      def initialize(directory)
        @directory = directory
      end

      def capture(name, editor)
        FileUtils.mkdir_p(@directory)
        path = File.join(@directory, "#{name.tr(".", "_")}.png")
        raise "could not capture visible Xvfb frame" unless system("import", "-window", "root", path)

        load_frame(path, editor)
        assert_current_row
        assert_caret
      end

      private

      def load_frame(path, editor)
        @image = read_frame(path)
        @editor = editor
        @origin = editor.viewport.map_to_global(::Qt::QPointF.new).to_point
        @caret = editor.cursor_rect
      end

      def read_frame(path)
        data = File.binread(path)
        buffer = ::FFI::MemoryPointer.new(:uint8, data.bytesize)
        buffer.put_bytes(0, data)
        image = ::Qt::QImage.new
        raise "could not load captured frame" unless image.load_from_data(buffer, data.bytesize, "PNG")

        image
      end

      def assert_current_row
        y = @caret.y + (@caret.height / 2)
        raise "current-row background failed to paint" unless row_colors(y).include?("#343a46")

        assert_adjacent_rows(y)
      end

      def assert_adjacent_rows(vertical)
        [vertical - @caret.height, vertical + @caret.height].each do |other_y|
          next unless other_y.between?(0, @editor.viewport.height - 1)

          raise "previous-row background failed to clear" if row_colors(other_y).include?("#343a46")
        end
      end

      def row_colors(vertical)
        width = @editor.viewport.width
        (1..12).map { |index| color_at(width * index / 13, vertical) }
      end

      def assert_caret
        width = [@editor.font_metrics.horizontal_advance(" ", 1), 4].max
        assert_caret_bounds(width)
        pixels = caret_colors(width)
        raise "block caret failed to paint" unless pixels.include?("#61afef")
      end

      def caret_colors(width)
        [1, @caret.height / 2, @caret.height - 2].flat_map do |dy|
          (3...width).map { |dx| color_at(@caret.x + dx, @caret.y + dy) }
        end
      end

      def assert_caret_bounds(width)
        return if @caret.x >= 0 && @caret.x + width <= @editor.viewport.width

        raise "block caret is clipped by the viewport"
      end

      def color_at(horizontal, vertical)
        @image.pixel_color((@origin.x + horizontal).round, (@origin.y + vertical).round).name
      end
    end
  end
end
