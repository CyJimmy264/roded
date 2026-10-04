module Roded
  # Connects picker contexts to reusable core candidate providers.
  module PickerProviderOperations
    private

    def picker_for(kind)
      candidates = picker_candidates_for(kind)
      Picker.new(candidates, history: @picker_query_history.fetch(kind, [])) if candidates
    end

    def picker_candidates_for(kind)
      provider = picker_providers[kind]
      provider&.call
    end

    def picker_providers
      standard_picker_providers.merge(path_picker_providers)
    end

    def standard_picker_providers
      {
        command: -> { command_names },
        switch_buffer: -> { buffers.map(&:name) },
        kill_ring: -> { kill_ring.items },
        line_search: -> { line_candidates },
        major_mode: -> { SyntaxHighlighter::MODES.map(&:to_s) }
      }
    end

    def path_picker_providers
      {
        open: -> { @file_path_provider.candidates },
        save: -> { @file_path_provider.candidates },
        save_as: -> { @file_path_provider.candidates }
      }
    end

    def line_candidates
      current_buffer.lines.each_with_index.map do |line, index|
        format("%<line>4d: %<text>s", line: index + 1, text: line)
      end
    end
  end
end
