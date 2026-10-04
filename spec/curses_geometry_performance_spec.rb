require "spec_helper"
require "roded/frontends/curses"

RSpec.describe Roded::Frontends::CursesTextGeometry, "linear horizontal scrolling" do
  it "matches legacy origins at every offset in tabs, wide characters and partial graphemes" do
    ["abcdef", "a\tb\tc", "界🙂e\u0301x", "👨‍👩‍👧‍👦xyz", "🇺🇸👍🏽abc"].each do |line|
      (0..line.length).each do |point|
        (0..line.length).each do |origin|
          [0, 1, 2, 4, 8].each do |width|
            expected = legacy_origin(line, point, origin, width)
            expect(described_class.horizontal_origin(line, point, origin, width)).to eq(expected),
                                                                                     [line, point, origin,
                                                                                      width].inspect
          end
        end
      end
    end
  end

  def legacy_origin(line, point, origin, width)
    return point if point < origin

    while width.positive? && described_class.column(line, point) - described_class.column(line, origin) >= width
      cluster = line[origin..].each_grapheme_cluster.first
      break unless cluster

      origin += cluster.length
    end
    origin
  end
end
