module Roded
  module Frontends
    # Decodes terminal input and wakes the read loop for quit and resize.
    module CursesInputOperations
      def next_event
        logger.debug("next_event: read_key")
        key = read_key
        logger.debug("next_event: read_key: #{key.inspect}")
        return unless key
        return handle_wake_event if key == :quit_signal
        return Event.new(:paste, { text: key.text }) if key.is_a?(CursesInputDecoder::PasteInput)

        Event.new(:key, { key: })
      end

      private

      def read_key
        @input_decoder.read_key(@stdin, @wake_r)
      end

      def install_resize_handler
        @resize_pending = false
        @previous_winch_handler = Signal.trap("WINCH") do
          @resize_pending = true
          wake_getch
        end
      end

      def handle_wake_event
        drain_wake_pipe
        return resize_event if @resize_pending

        Event.new(:quit, {})
      end

      def resize_event
        @resize_pending = false
        ::Curses.resizeterm(0, 0)
        Event.new(:resize, {})
      end

      def enable_bracketed_paste
        $stdout.write("\e[?2004h")
        $stdout.flush
      end

      def disable_bracketed_paste
        $stdout.write("\e[?2004l")
        $stdout.flush
      end

      def wake_getch(_payload = nil)
        @wake_w.write_nonblock(".")
      rescue IO::WaitWritable, Errno::EPIPE
        nil
      end

      def drain_wake_pipe
        loop { @wake_r.read_nonblock(64) }
      rescue IO::WaitReadable
        nil
      end
    end
  end
end
