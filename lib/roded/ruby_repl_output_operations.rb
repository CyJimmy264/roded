module Roded
  # Formats stdout, stderr, result, and lifecycle messages for *ruby*.
  module RubyReplOutputOperations
    private

    def format_repl_output(payload)
      output = payload.fetch(:stdout, payload.fetch(:output, "")).dup
      append_stderr(output, payload)
      append_result(output, payload)
      append_exit_status(output, payload)
      output
    end

    def append_stderr(output, payload)
      stderr = payload.fetch(:stderr, "")
      output << "[stderr] #{stderr}" unless stderr.empty?
    end

    def append_result(output, payload)
      output << "=> #{payload[:result]}\n" if payload.key?(:result)
      output << "#{payload[:error]}\n" if payload[:error]
    end

    def append_exit_status(output, payload)
      output << "REPL interaction closed.\n" if payload[:exit]
      output << "> " unless payload[:exit]
    end
  end
end
