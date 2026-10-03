require "tmpdir"
require "fileutils"

ENV["RODED_LOG_PATH"] = File.join(Dir.tmpdir, "roded-test-#{Process.pid}.log")
ENV["RODED_LOG_LEVEL"] = "FATAL"
ENV["XDG_CONFIG_HOME"] = File.join(Dir.tmpdir, "roded-spec-config-#{Process.pid}")
ENV["QT_QPA_PLATFORM"] = "offscreen"
FileUtils.mkdir_p(ENV.fetch("XDG_CONFIG_HOME"))

require "roded"
require_relative "support/fake_frontend"

RSpec.configure do |config|
  FileUtils.mkdir_p("tmp")

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = "tmp/rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
