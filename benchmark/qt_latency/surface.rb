require_relative "x11"

module Roded
  module Benchmarking
    # Polls the actual server-side frame, independently of the editor's Ruby GVL.
    class LatencySurface
      CARET = 0x61afef

      def initialize
        @display = LatencyX11.XOpenDisplay(ENV.fetch("DISPLAY"))
        raise "could not open private X display" if @display.null?

        @root = LatencyX11.XDefaultRootWindow(@display)
      end

      def close = LatencyX11.XCloseDisplay(@display)

      def key(name)
        modifiers, symbol = name.split("+")
        unless symbol
          symbol = modifiers
          modifiers = nil
        end
        fake_key(modifiers, true) if modifiers
        fake_key(symbol, true)
        fake_key(symbol, false)
        fake_key(modifiers, false) if modifiers
        LatencyX11.XFlush(@display)
      end

      def visible?(current, previous = nil)
        rectangle = bounds(current, previous)
        image = LatencyX11.XGetImage(@display, @root, *rectangle, 0xffffffff, 2)
        raise "could not read private X frame: root=#{@root}, rectangle=#{rectangle}" if image.null?

        caret?(image, current, rectangle) && (!previous || !caret?(image, previous, rectangle))
      ensure
        LatencyX11.XDestroyImage(image) if image && !image.null?
      end

      private

      def fake_key(symbol, pressed)
        code = LatencyX11.XKeysymToKeycode(@display, LatencyX11.XStringToKeysym(symbol))
        raise "unknown X key #{symbol}" if code.zero?

        LatencyX11.XTestFakeKeyEvent(@display, code, pressed ? 1 : 0, 0)
      end

      def bounds(current, previous)
        points = [current, previous].compact
        x = points.map { |point| point.fetch("x") }.min
        y = points.map { |point| point.fetch("y") }.min
        right = maximum_edge(points, "x", "width")
        bottom = maximum_edge(points, "y", "height")
        [x, y, right - x, bottom - y]
      end

      def maximum_edge(points, axis, size) = points.map { |point| point.fetch(axis) + point.fetch(size) }.max

      def caret?(image, point, rectangle)
        [1, point.fetch("height") - 2].any? do |dy|
          (3...point.fetch("width")).any? do |dx|
            pixel = LatencyX11.XGetPixel(image, point.fetch("x") - rectangle[0] + dx,
                                         point.fetch("y") - rectangle[1] + dy)
            pixel & 0xffffff == CARET
          end
        end
      end
    end
  end
end
