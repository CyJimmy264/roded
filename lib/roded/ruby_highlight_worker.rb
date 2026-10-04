require "open3"
require "rbconfig"
require_relative "ruby_highlight_result_operations"

module Roded
  # Bounds queued work to the latest immutable request per buffer.
  class RubyHighlightWorker
    include RubyHighlightResultOperations

    def initialize(&callback)
      @callback = callback
      @mutex = Mutex.new
      @condition = ConditionVariable.new
      @pending = {}
      @latest = {}
      @sequence = 0
      @closed = false
    end

    def submit(buffer_id:, revision:, lines:, signatures:)
      @mutex.synchronize do
        return if @closed

        @sequence += 1
        job = { id: @sequence, buffer_id:, revision:, lines:, signatures: }.freeze
        @pending[buffer_id] = job
        @latest[buffer_id] = job
        @thread = Thread.new { run_process } unless @thread&.alive?
        @condition.signal
        job.fetch(:id)
      end
    end

    def cancel(buffer_id)
      @mutex.synchronize do
        @pending.delete(buffer_id)
        @latest.delete(buffer_id)
      end
    end

    def close
      pid = @mutex.synchronize do
        @closed = true
        @pending.clear
        @latest.clear
        @condition.broadcast
        @pid
      end
      terminate(pid)
      @thread&.join
    end

    private

    def run_process
      start_process
    rescue StandardError => e
      fail_requests(e)
    ensure
      reset_process
    end

    def start_process
      path = File.expand_path("ruby_highlight_server.rb", __dir__)
      Open3.popen2(RbConfig.ruby, "-I", $LOAD_PATH.join(File::PATH_SEPARATOR), path) do |input, output, waiter|
        closed = register_process(waiter.pid)
        process_jobs(input.binmode, output.binmode) unless closed
      end
    end

    def register_process(pid)
      closed = @mutex.synchronize do
        @pid = pid
        @closed
      end
      terminate(pid) if closed
      closed
    end

    def reset_process
      @mutex.synchronize do
        @pid = nil
        @thread = nil
        @thread = Thread.new { run_process } if !@closed && !@pending.empty?
      end
    end

    def process_jobs(input, output)
      while (job = next_job)
        Marshal.dump(job, input)
        input.flush
        changes = read_changes(output)
        deliver(job, changes:)
      end
    end

    def read_changes(output)
      changes = []
      # Each bounded frame yields between native deserializations, even for a whole-file context change.
      while (batch = Marshal.load(output)) # rubocop:disable Security/MarshalLoad -- private pipe from our lexer child
        changes.concat(batch)
      end
      freeze_changes(changes)
    end

    def next_job
      @mutex.synchronize do
        @condition.wait(@mutex) while @pending.empty? && !@closed
        @pending.shift&.last unless @closed
      end
    end

    def terminate(pid)
      Process.kill("TERM", pid) if pid
    rescue Errno::ESRCH
      nil
    end
  end
end
