require "spec_helper"

RSpec.describe Roded::CommandHandler do
  it "routes buffer commands through the command context contract" do
    context = instance_double(Roded::ApplicationCommandContext)
    allow(context).to receive_messages(focus: :buffer, page_size: 12)
    expect(context).to receive(:break_kill_sequence).with(:move_down)
    expect(context).to receive(:invoke_buffer_operation).with(:move_cursor_down)
    expect(context).to receive(:publish_ui_update).with(:move_cursor, { direction: :down })

    command = Roded::EditorCommand.new(:move_down, {}, nil, nil)
    described_class.new(context).handle(command)
  end

  it "routes minibuffer commands through the command context contract" do
    minibuffer = instance_double(Roded::Minibuffer)
    context = instance_double(Roded::ApplicationCommandContext, focus: :minibuffer, minibuffer:)
    allow(context).to receive(:break_kill_sequence)
    expect(minibuffer).to receive(:move_left)
    expect(context).to receive(:render_minibuffer)

    command = Roded::EditorCommand.new(:move_left, {}, nil, nil)
    described_class.new(context).handle(command)
  end
end
