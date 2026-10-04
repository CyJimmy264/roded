require "logger"
require "fileutils"

module Roded
  # Provides the application logger and scoped log-level configuration.
  module Logging
    DEFAULT_LOG_PATH = File.join(Dir.home, ".cache", "roded", "roded.log")

    def self.logger
      @logger ||= begin
        log_path = ENV.fetch("RODED_LOG_PATH", DEFAULT_LOG_PATH)
        FileUtils.mkdir_p(File.dirname(log_path))
        logger = Logger.new(log_path)
        level_name = ENV.fetch("RODED_LOG_LEVEL", "INFO").to_s.upcase
        logger.level = Logger.const_defined?(level_name) ? Logger.const_get(level_name) : Logger::INFO
        logger
      end
    end

    def self.logger=(new_logger)
      @logger = new_logger
    end

    def logger
      Logging.logger
    end
  end
end
