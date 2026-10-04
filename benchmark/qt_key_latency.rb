#!/usr/bin/env ruby

require "rbconfig"

# No desktop display or user configuration participates in this measurement.
unless ENV["RODED_KEY_LATENCY_XVFB"] == "1"
  exec({ "RODED_KEY_LATENCY_XVFB" => "1" }, "xvfb-run", "-a", "-s", "-screen 0 1920x1080x24",
       RbConfig.ruby, __FILE__, *ARGV)
end

require_relative "../lib/roded"
require_relative "roded/isolation"
require_relative "qt_latency/runner"

Roded::Benchmarking::Isolation.run(xvfb: true) do
  Roded::Benchmarking::LatencyRunner.new(ARGV).run
end
