require "tempfile"

# rubocop:disable Metrics/BlockLength
RSpec.describe Roded::Application do
  subject(:application) { described_class.new }

  let(:frontend) { FakeFrontend.new }

  before do
    application.instance_variable_set(:@frontends, [frontend])
  end

  it "opens the command minibuffer from M-x and broadcasts its state" do
    application.handle_event(Roded::Event.new(:key, { key: "Esc" }))
    application.handle_event(Roded::Event.new(:key, { key: "x" }))

    expect(application.focus).to eq(:minibuffer)
    expect(frontend.focus).to eq(:minibuffer)
    expect(frontend.commands.last).to eq(
      Roded::Command.new(:minibuffer_render, { prompt: "M-x ", text: "", cursor: 0 })
    )
  end

  it "submits M-x quit through routed key events" do
    %w[Esc x q u i t Enter].each do |key|
      application.handle_event(Roded::Event.new(:key, { key: key }))
    end

    expect(application.focus).to eq(:buffer)
    expect(frontend.focus).to eq(:buffer)
    expect(frontend.commands).to include(Roded::Command.new(:quit, {}))
  end

  it "opens a file and renders the loaded buffer" do
    Tempfile.create("roded-open") do |file|
      file.write("alpha\nbeta\n")
      file.flush

      application.open_file(file.path)

      expect(application.current_buffer.filename).to eq(file.path)
      expect(application.current_buffer.lines).to eq(%w[alpha beta])
      expect(application.current_buffer.cursor_pos).to eq({ row: 0, col: 0 })
      expect(frontend.buffers.last).to eq(application.current_buffer)
      expect(frontend.renders.last).to eq(application.current_buffer)
      expect(frontend.messages.last).to eq("File '#{file.path}' opened.")
    end
  end

  it "saves the current buffer to disk" do
    Tempfile.create("roded-save") do |file|
      buffer = Roded::Buffer.new(file.path)
      buffer.lines = %w[saved content]
      buffer.filename = file.path
      application.add_buffer(buffer)

      application.save_file(file.path)

      expect(File.read(file.path)).to eq("saved\ncontent")
      expect(frontend.messages.last).to eq("File '#{file.path}' saved.")
    end
  end
end
# rubocop:enable Metrics/BlockLength
