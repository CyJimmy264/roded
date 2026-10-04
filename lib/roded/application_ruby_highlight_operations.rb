require_relative "ruby_highlight_worker"
require_relative "ruby_highlight_state"

module Roded
  # Applies background lexical results only on the core event thread and matching revision.
  module ApplicationRubyHighlightOperations
    BACKGROUND_RUBY_MINIMUM_LINES = 1500

    def syntax_highlighting_pending?
      @ruby_highlight_states&.values&.any?(&:job_id) || false
    end

    def shutdown_syntax_highlighting
      @ruby_highlight_worker&.close
    end

    private

    def document_tokens(buffer, mode, lines)
      return synchronous_document_tokens(buffer, mode, lines) unless background_ruby?(mode, lines)

      @ruby_highlight_states ||= {}.compare_by_identity
      state = @ruby_highlight_states[buffer]
      return seed_ruby_highlighting(buffer, lines) unless state

      state.prepare(buffer.revision, lines)
      job_id = ruby_highlight_worker.submit(buffer_id: buffer.object_id, revision: buffer.revision,
                                            lines:, signatures: state.signatures)
      state.submitted(job_id)
      state.tokens
    end

    def synchronous_document_tokens(buffer, mode, lines)
      forget_ruby_highlighting(buffer)
      @syntax_highlighter.spans(mode, lines)
    end

    def background_ruby?(mode, lines)
      mode == :ruby && lines.length >= BACKGROUND_RUBY_MINIMUM_LINES
    end

    def seed_ruby_highlighting(buffer, lines)
      tokens = @syntax_highlighter.spans(:ruby, lines)
      @ruby_highlight_states[buffer] = RubyHighlightState.new(buffer.revision, lines, tokens)
      tokens
    end

    def ruby_highlight_worker
      @ruby_highlight_worker ||= RubyHighlightWorker.new do |result|
        push_event(InputEvent.new(:syntax_result, result))
      end
    end

    def handle_syntax_result(payload)
      buffer = syntax_result_buffer(payload)
      return unless buffer

      state = @ruby_highlight_states&.[](buffer)
      return unless state&.apply(payload[:id], payload.fetch(:changes), failed: payload[:error])

      update_highlight_snapshot(buffer, state.tokens)
      publish_highlight_result(buffer, payload)
    end

    def publish_highlight_result(buffer, payload)
      logger.warn("Background highlighting failed: #{payload[:error]}") if payload[:error]
      publish_ui_update(UIUpdate.new(:render, {})) if windows.any? { |window| window.buffer.equal?(buffer) }
    end

    def syntax_result_buffer(payload)
      buffers.find do |buffer|
        buffer.object_id == payload[:buffer_id] && buffer.mode == :ruby && buffer.revision == payload[:revision]
      end
    end

    def update_highlight_snapshot(buffer, tokens)
      cached = @document_snapshots&.[](buffer)
      return unless cached && cached[:revision] == buffer.revision && cached[:mode] == :ruby

      cached[:content] = cached[:content].merge(tokens:).freeze
    end

    def forget_ruby_highlighting(buffer)
      @ruby_highlight_states&.delete(buffer)
      @ruby_highlight_worker&.cancel(buffer.object_id)
    end
  end
end
