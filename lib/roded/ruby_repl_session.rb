require "stringio"

module Roded
  # Runs persistent Ruby evaluation away from the UI thread and reports results
  # back through the application's event queue.
  class RubyReplSession
    class ExitInteraction < StandardError; end

    attr_reader :thread

    def initialize(editor_api, &post_event)
      @editor_api = editor_api
      @post_event = post_event
      @history = []
      @mutex = Mutex.new
    end

    def history
      @mutex.synchronize { @history.map { |entry| entry.dup.freeze }.freeze }
    end

    def start_evaluation?(code)
      return false if thread&.alive?

      @mutex.synchronize { @history << code.to_s.dup.freeze }
      ready = Queue.new
      @thread = Thread.new { evaluate_code(code.to_s, ready) }
      ready.pop
      true
    end

    def interrupt
      return false unless thread&.alive?

      thread.raise(Interrupt)
      true
    rescue ThreadError
      false
    end

    def close
      interrupt
      thread&.join(1)
    end

    private

    def evaluate_code(code, ready)
      publish(evaluate_payload(code, ready))
    ensure
      context.clear_output
    end

    def evaluate_payload(code, ready)
      ready << true
      context.start_output_capture
      with_output_capture { payload(result: evaluate(code).inspect) }
    rescue ExitInteraction
      payload(exit: true)
    rescue Interrupt
      payload(error: "Interrupt")
    rescue SystemExit, ScriptError, StandardError => e
      payload(error: "#{e.class}: #{e.message}")
    end

    def with_output_capture
      original_stdout = $stdout
      original_stderr = $stderr
      $stdout = context.stdout
      $stderr = context.stderr
      yield
    ensure
      Thread.handle_interrupt(Interrupt => :never) do
        $stdout = original_stdout if original_stdout
        $stderr = original_stderr if original_stderr
      end
    end

    def evaluate(code)
      context.binding.eval(code, "(roded-repl)", history.length)
    end

    def payload(values)
      { stdout: context.stdout&.string.to_s, stderr: context.stderr&.string.to_s }.merge(values)
    end

    def publish(payload)
      @post_event.call(Event.new(:repl_result, payload.freeze))
    end

    def context
      @context ||= Context.new(@editor_api)
    end

    # Holds persistent locals and redirects the common Kernel output methods.
    class Context
      attr_accessor :stdout, :stderr

      def initialize(editor)
        @editor = editor
        @stdout = nil
        @stderr = nil
        @binding = Kernel.binding
      end

      attr_reader :editor, :binding

      def clear_output
        @stdout = nil
        @stderr = nil
      end

      def start_output_capture
        @stdout = StringIO.new
        @stderr = StringIO.new
      end

      def puts(*values) = stdout&.puts(*values)

      def print(*values) = stdout&.print(*values)

      def warn(*values) = stderr&.puts(*values)

      def p(*values)
        values.each { |value| stdout&.puts(value.inspect) }
        values.length == 1 ? values.first : values
      end

      def exit(*)
        raise ExitInteraction
      end
    end
  end
end
