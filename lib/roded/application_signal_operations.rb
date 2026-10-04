module Roded
  # Installs and restores signal handlers for the application loop.
  module ApplicationSignalOperations
    def trap_signals
      %w[HUP INT QUIT TERM].each do |signal|
        @signal_handlers[signal] = trap(signal) do |received|
          push_event(Event.new(:signal, { signal: received }))
        end
      end
    end

    def restore_signal_handlers
      restore_signals
    end

    private

    def restore_signals
      @signal_handlers.each { |signal, handler| trap(signal, handler) }
      @signal_handlers.clear
    end
  end
end
