RSpec.describe Roded::Application, "binding help" do
  it "shows actual keymap entries and commands through C-h b and M-x" do
    application = described_class.new
    application.startup
    calls = 0
    application.register_command(
      "inspect-from-help",
      binding: "M-q",
      description: "Command added by the user"
    ) { |_editor| calls += 1 }

    %w[C-h b].each { |key| application.handle_event(Roded::Event.new(:key, { key: })) }
    help_buffer = application.current_buffer

    expect(help_buffer.name).to eq("*Bindings*")
    expect(help_buffer.readonly).to be(true)
    expect(help_buffer.modified?).to be(false)
    expect(help_buffer.to_s).to include("C-h b", "describe_bindings", "M-q", "inspect-from-help")
    application.handle_event(Roded::Event.new(:key, { key: "M-q" }))
    expect(calls).to eq(1)

    command_keys = ["Esc", "x", *"describe-bindings".chars, "Enter"]
    command_keys.each { |key| application.handle_event(Roded::Event.new(:key, { key: })) }

    expect(application.current_buffer).to equal(help_buffer)
    expect(help_buffer.to_s).to include("Command added by the user")
    original_text = help_buffer.to_s
    help_buffer.insert_char("x", at: { row: 0, col: 0 })
    expect(help_buffer.to_s).to eq(original_text)
  end
end
