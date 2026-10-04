require "open3"
require "rbconfig"
require "socket"
require "time"

module Roded
  module Benchmarking
    # Records the measurement implementation and machine, not just the Git revision.
    module Environment
      def self.capture
        {
          recorded_at: Time.now.utc.iso8601, ruby: RUBY_DESCRIPTION, platform: RUBY_PLATFORM,
          host: Socket.gethostname, cpu: cpu_model, yjit: yjit_enabled?,
          gems: gem_versions,
          git_revision: git("rev-parse", "HEAD"), git_dirty: !git("status", "--porcelain").empty?,
          harness_sha256: harness_digest,
          qt_platform: ENV.fetch("QT_QPA_PLATFORM", "offscreen"),
          ruby_options: ENV.fetch("RUBYOPT", nil), gc_environment: gc_environment
        }
      end

      def self.yjit_enabled? = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?

      def self.gem_versions = Gem.loaded_specs.transform_values { |spec| spec.version.to_s }

      def self.gc_environment = ENV.select { |key, _value| key.start_with?("RUBY_GC_") }

      def self.git(*)
        stdout, _stderr, status = Open3.capture3("git", *, chdir: File.expand_path("../..", __dir__))
        status.success? ? stdout.strip : "unknown"
      end

      def self.cpu_model
        return RbConfig::CONFIG.fetch("host_cpu") unless File.file?("/proc/cpuinfo")

        File.read("/proc/cpuinfo")[/^model name\s*:\s*(.+)$/, 1] || RbConfig::CONFIG.fetch("host_cpu")
      end

      def self.harness_digest
        files = Dir[File.join(__dir__, "*.rb")] + [File.expand_path("../run.rb", __dir__)]
        Digest::SHA256.hexdigest(files.map { |path| "#{File.basename(path)}\0#{File.read(path)}" }.join("\0"))
      end
    end
  end
end
