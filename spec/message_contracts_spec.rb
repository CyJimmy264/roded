RSpec.describe "editor message contracts" do
  it "distinguishes incoming facts from routed editor commands and UI updates" do
    input = Roded::InputEvent.new(:key, { key: "C-n" })
    command = Roded::EditorCommand.new(:move_down, {}, :qt, 42)
    update = Roded::Command.new(:render, {})

    expect(input).to be_a(Roded::InputEvent)
    expect(command).to be_a(Roded::EditorCommand)
    expect(update).to be_a(Roded::UIUpdate)
    expect(Roded::Event).to equal(Roded::InputEvent)
  end

  it "rejects input facts at the editor command handler boundary" do
    handler = Roded::CommandHandler.new(Object.new)

    expect do
      handler.handle(Roded::InputEvent.new(:move_down, {}))
    end.to raise_error(ArgumentError, /expected EditorCommand/)
  end

  it "rejects editor commands at the application input boundary" do
    application = Roded::Application.new

    expect do
      application.handle_event(Roded::EditorCommand.new(:move_down, {}, nil, nil))
    end.to raise_error(ArgumentError, /expected InputEvent/)
  end
end
