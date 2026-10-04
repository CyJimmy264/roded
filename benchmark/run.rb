#!/usr/bin/env ruby

require "rbconfig"

# Xvfb must be created before Qt loads; never reuse the desktop DISPLAY.
if ARGV.include?("--qt-xvfb") && ENV["RODED_BENCHMARK_XVFB"] != "1"
  exec({ "RODED_BENCHMARK_XVFB" => "1" }, "xvfb-run", "-a", "-s", "-screen 0 1280x800x24",
       RbConfig.ruby, __FILE__, *ARGV)
end

require_relative "../lib/roded"
require_relative "roded/cli"

exit Roded::Benchmarking::CLI.new.run(ARGV)
