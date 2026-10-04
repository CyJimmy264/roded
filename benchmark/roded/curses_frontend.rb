require_relative "../../lib/roded/frontends/curses"
require_relative "memory_screen"

module Roded
  module Benchmarking
    # Uses the production renderer with an in-memory, monochrome screen.
    class CursesFrontend < NullFrontend
      attr_reader :screen

      def initialize
        super
        @screen = MemoryScreen.new
        @frontend = Frontends::Curses.allocate
        @frontend.send(:initialize_editor_state)
        @frontend.instance_variable_set(:@screen, @screen)
        @frontend.send(:initialize_minibuffer)
      end

      def handle_command(command) = @frontend.handle_command(command)
    end
  end
end
