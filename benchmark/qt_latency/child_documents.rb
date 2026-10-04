module Roded
  module Benchmarking
    # Prepares visited buffers before measuring keys; source files stay read-only.
    module LatencyChildDocuments
      private

      def build_application(fixture)
        application = Application.new
        documents = document_fixtures(fixture).map { |source| build_buffer(application, source) }
        application.add_window(Window.new(documents.first))
        visit_documents(application, documents)
        position(application.current_window, fixture.line_count)
        application
      end

      def visit_documents(application, documents)
        documents.each do |buffer|
          application.current_window.buffer = buffer
          application.editor_snapshot
        end
        application.current_window.buffer = documents.first
      end

      def document_fixtures(fixture)
        Array.new(@config.fetch(:buffers), fixture) +
          @config.fetch(:extra_files).map { |path| LatencyFileFixture.new(path) }
      end

      def build_buffer(application, fixture)
        Buffer.new("latency-#{application.buffers.length}-#{fixture.profile}").tap do |buffer|
          buffer.major_mode = fixture.mode
          buffer.load_text(fixture.text)
          application.add_buffer(buffer)
        end
      end

      def position(window, lines)
        row = @config[:start_row] || (lines / 2)
        col = @config.fetch(:start_col)
        line = window.buffer.lines[row]
        raise ArgumentError, "start position is outside the fixture" unless line && col <= line.length

        window.point = { row:, col: }
        window.top_line = [row - 10, 0].max
        window.left_column = [col - 20, 0].max
      end
    end
  end
end
