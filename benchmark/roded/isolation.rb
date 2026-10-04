require "tmpdir"

module Roded
  module Benchmarking
    # Uses private configuration and keeps Qt away from the user's desktop.
    module Isolation
      def self.run(xvfb:, &)
        Dir.mktmpdir("roded-benchmark-") do |directory|
          values = { "XDG_CONFIG_HOME" => "#{directory}/config", "XDG_CACHE_HOME" => "#{directory}/cache",
                     "QT_QPA_PLATFORM" => xvfb ? "xcb" : "offscreen" }
          FileUtils.mkdir_p(values.values_at("XDG_CONFIG_HOME", "XDG_CACHE_HOME"))
          with_environment(values) { with_logger(&) }
        end
      end

      def self.with_environment(values)
        original = values.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
        values.each { |key, value| ENV[key] = value }
        yield
      ensure
        original&.each { |key, value| value ? ENV[key] = value : ENV.delete(key) }
      end

      def self.with_logger
        previous = Logging.instance_variable_get(:@logger)
        logger = Logger.new(File::NULL, level: Logger::FATAL)
        Logging.logger = logger
        yield
      ensure
        logger&.close
        Logging.logger = previous
      end
    end
  end
end
