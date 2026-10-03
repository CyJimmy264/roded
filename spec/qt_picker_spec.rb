require "qt"
require_relative "../lib/roded/frontends/qt/editor_window"

RSpec.describe Roded::Frontends::QtEditorWindow do
  before(:context) { @qt_application = QApplication.new(0, ["roded-picker-spec"]) }

  after(:context) do
    QApplication.process_events
    @qt_application.quit
  end

  it "renders picker query and selection in the Qt echo area" do
    view = described_class.new
    view.render_picker(prompt: "M-x ", query: "u", selected_index: 0, candidates: %w[undo quit])

    echo = view.instance_variable_get(:@echo_area).widget
    expect(echo.text).to eq("M-x u\n> undo\n  quit")
  end
end
