module Roded
  # Displays the active keymap and command registry in a read-only buffer.
  module HelpOperations
    BINDINGS_BUFFER_NAME = "*Bindings*"

    def describe_bindings
      buffer = buffers.find { |candidate| candidate.name == BINDINGS_BUFFER_NAME }
      buffer ||= Buffer.new(BINDINGS_BUFFER_NAME)
      buffer.load_text(binding_help_text)
      buffer.readonly = true
      add_buffer(buffer) unless buffers.include?(buffer)
      switch_buffer(BINDINGS_BUFFER_NAME)
    end

    private

    def binding_help_text
      ["Roded key bindings", "", "Key bindings:", *binding_rows, "", "M-x commands:", *command_rows].join("\n")
    end

    def binding_rows
      @keymap.bindings.map do |binding|
        payload = binding[:payload] == "{}" ? "" : " #{binding[:payload]}"
        "#{binding[:key].ljust(20)} #{binding[:type]}#{payload}"
      end
    end

    def command_rows
      command_catalog.map do |command|
        description = command[:description].to_s
        suffix = description.empty? ? "" : " — #{description}"
        "#{command[:name]}#{suffix}"
      end
    end
  end
end
