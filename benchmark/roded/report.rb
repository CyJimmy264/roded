require "json"
require "fileutils"

module Roded
  module Benchmarking
    # Persists raw operation samples alongside the readable summary.
    module Report
      def self.write(path, report)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "#{JSON.pretty_generate(report)}\n")
      end

      def self.print(report, output: $stdout)
        output.puts "layer          lines scenario                  median ms     p95 ms     max ms   objects/op"
        report.fetch(:results).sort_by { |row| row.values_at(:layer, :lines, :scenario) }.each do |row|
          output.puts format_row(row)
        end
        print_comparison(report[:comparison], output) if report[:comparison]
      end

      def self.format_row(row)
        format("%<layer>-12s %<lines>7d %<scenario>-24s %<median_ms>10.3f %<p95_ms>10.3f " \
               "%<max_ms>10.3f %<allocated_objects_per_operation>12.1f", row.merge(row.fetch(:metrics)))
      end

      def self.print_comparison(rows, output)
        output.puts "\nBaseline comparison (median / p95 / allocations):"
        rows.each { |row| output.puts format_comparison(row) }
      end

      def self.format_comparison(row)
        values = row.merge(
          allocations: row[:allocations_change_percent]&.then { |value| format("%<value>+.1f%%", value:) } || "n/a",
          status: row[:regression] ? " REGRESSION" : ""
        )
        format("%<layer>-12s %<lines>7d %<scenario>-24s %<change_percent>+8.1f%% " \
               "%<p95_change_percent>+8.1f%% %<allocations>s%<status>s", values)
      end
    end
  end
end
