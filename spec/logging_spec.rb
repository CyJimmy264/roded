require "spec_helper"

module LoggingSpecSupport
  def with_temporary_log(path)
    original = logger_environment
    temporary = create_temporary_logger(path)
    yield temporary
  ensure
    restore_logger(temporary, original) if original
  end

  def logger_environment
    [Roded::Logging.logger, ENV.fetch("RODED_LOG_PATH", nil), ENV.fetch("RODED_LOG_LEVEL", nil)]
  end

  def create_temporary_logger(path)
    ENV["RODED_LOG_PATH"] = path
    ENV["RODED_LOG_LEVEL"] = "DEBUG"
    Roded::Logging.logger = nil
    Roded::Logging.logger
  end

  def restore_logger(logger, original)
    logger.close
    Roded::Logging.logger = original.first
    ENV["RODED_LOG_PATH"] = original[1]
    ENV["RODED_LOG_LEVEL"] = original[2]
  end
end

RSpec.describe Roded::Logging do
  include LoggingSpecSupport

  it "writes diagnostics to its configured file without terminal output" do
    Dir.mktmpdir("roded-logging") do |directory|
      path = File.join(directory, "editor.log")

      with_temporary_log(path) do |logger|
        expect { logger.info("editor runtime ready") }
          .to output("").to_stdout.and output("").to_stderr
      end

      expect(File.read(path)).to include("editor runtime ready")
    end
  end
end
