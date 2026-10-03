RSpec.describe Roded::EditorSession do
  it "owns application buffers and the logical window tree" do
    application = Roded::Application.new
    application.startup
    session = application.session
    buffer = Roded::Buffer.new("second")
    application.add_buffer(buffer)

    expect(session.buffers).to eq(application.buffers)
    expect(session.current_window).to equal(application.current_window)
    expect(session.window_layout.windows).to eq(application.windows)
    expect(application.instance_variables).not_to include(
      :@buffers, :@windows, :@window_layout, :@current_buffer, :@current_window
    )

    application.switch_buffer("second")

    expect(session.current_window).to equal(application.current_window)
    expect(session.current_window.buffer).to equal(buffer)
  end
end
