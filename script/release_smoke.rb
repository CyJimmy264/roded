#!/usr/bin/env ruby

require "rubygems/package"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"

# Verifies the artifact itself, including its lexer child, without installing globally.
class ReleaseSmoke
  REQUIRED = %w[lib/roded.rb lib/roded/version.rb lib/roded/ruby_highlight_server.rb
                lib/roded/frontends/curses.rb lib/roded/frontends/qt.rb bin/roded README.md CHANGELOG.md LICENSE].freeze
  EXCLUDED = %w[benchmark/ spec/ script/ .agents/ tmp/ pkg/ AGENTS.md GOAL.md PLAN.org].freeze
  PROBE = <<~'RUBY'.freeze
    require "roded"
    require "timeout"
    expected_root, expected_version = ARGV
    abort "wrong packaged version" unless Roded::VERSION == expected_version
    loaded = $LOADED_FEATURES.find { |path| path.end_with?("/roded.rb") }
    abort "loaded checkout instead of package" unless loaded.start_with?(expected_root)
    abort "core eagerly loaded frontend" if $LOADED_FEATURES.any? { |path| path.end_with?("/qt.rb", "/curses.rb") }
    buffer = Roded::Buffer.new("package.rb").load_text("puts 42\n")
    view = Roded::Window.new(buffer)
    buffer.insert_char("#", at: view.point)
    abort "packaged undo failed" unless buffer.undo && buffer.to_s == "puts 42\n"
    completed = Queue.new
    worker = Roded::RubyHighlightWorker.new { |result| completed << result }
    begin
      worker.submit(buffer_id: 1, revision: 1, lines: ["42".freeze].freeze, signatures: [nil].freeze)
      result = Timeout.timeout(10) { completed.pop }
      abort "packaged lexer child failed" if result[:error] || result[:changes].empty?
    ensure
      worker.close
    end
    require "roded/frontends/curses"
    require "roded/frontends/qt"
    puts "Packaged Roded #{Roded::VERSION}: core, undo, lexer child and both frontend loaders passed"
  RUBY

  def initialize(path)
    @package = Gem::Package.new(path)
  end

  def run
    @package.verify
    verify_contents
    Dir.mktmpdir("roded-release-") do |directory|
      @package.extract_files(directory)
      run_probe(directory)
    end
  end

  private

  def verify_contents
    files = @package.contents
    missing = REQUIRED - files
    raise "missing package files: #{missing.join(", ")}" unless missing.empty?

    unwanted = files.select { |path| path.start_with?(*EXCLUDED) }
    raise "development files in package: #{unwanted.join(", ")}" unless unwanted.empty?
  end

  def run_probe(directory)
    environment = { "RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil, "QT_QPA_PLATFORM" => "offscreen",
                    "XDG_CONFIG_HOME" => File.join(directory, "config"),
                    "XDG_CACHE_HOME" => File.join(directory, "cache"),
                    "RODED_LOG_PATH" => File.join(directory, "roded.log") }
    FileUtils.mkdir_p(environment.values_at("XDG_CONFIG_HOME", "XDG_CACHE_HOME"))
    stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby, "-I", File.join(directory, "lib"),
                                            "-e", PROBE, directory, @package.spec.version.to_s, chdir: directory)
    raise "packaged runtime failed:\n#{stdout}#{stderr}" unless status.success?

    puts stdout
  end
end

abort "Usage: ruby script/release_smoke.rb pkg/roded-VERSION.gem" unless ARGV.length == 1
ReleaseSmoke.new(ARGV.first).run
