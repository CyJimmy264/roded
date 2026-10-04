require "qt"
require_relative "../lib/roded/frontends/qt/editor_window"

RSpec.describe Roded::Frontends::QtEditorWindow do
  before(:context) { @qt_application = QApplication.new(0, ["roded-syntax-spec"]) }

  after(:context) do
    QApplication.process_events
    @qt_application.quit
  end

  it "renders syntax token colors and mode in a Qt text pane" do
    view = described_class.new
    lines = ["def greet", "end"]
    view.render_layout(
      tree: { window_id: 10 }, active_window_id: 10,
      windows: [{
        id: 10, text: lines.join("\n"), lines:, tokens: Roded::SyntaxHighlighter.new.spans(:ruby, lines),
        point: { row: 0, col: 0 }, name: "sample.rb", mode: :ruby, modified: false,
        readonly: false, active: true
      }]
    )

    expect(view.editor.to_html).to include("#c678dd")
    modeline = view.instance_variable_get(:@panes).fetch(10).instance_variable_get(:@modeline)
    expect(modeline.text).to include("ruby")
  end
end
