module Roded
  # Drops superseded responses before publishing an immutable result to the core.
  module RubyHighlightResultOperations
    private

    def freeze_changes(changes)
      changes.each do |row|
        row[1].each(&:freeze).freeze
        row[2].freeze
        row.freeze
      end.freeze
    end

    def deliver(job, **result)
      accepted = @mutex.synchronize do
        @latest.delete(job.fetch(:buffer_id)) if @latest[job.fetch(:buffer_id)].equal?(job)
      end
      @callback.call(job.slice(:id, :buffer_id, :revision).merge(result).freeze) if accepted
    end

    def fail_requests(error)
      jobs = @mutex.synchronize do
        @pending.clear
        @latest.values.dup
      end
      jobs.each { |job| deliver(job, changes: [].freeze, error: error.message.dup.freeze) }
    end
  end
end
