require "qt"
require_relative "../lib/roded/frontends/qt/editor_window"

RSpec.describe Roded::Frontends::QtEditorWindow do
  before(:context) do
    @qt_application = QApplication.new(0, ["roded-spec"])
    @views = []
  end

  after(:context) do
    @views.each(&:close)
    QApplication.process_events
    @qt_application.quit
  end

  it "renders multiple read-only widgets inside a real Qt splitter" do
    view = described_class.new
    @views << view
    view.render_layout(
      tree: {
        direction: :vertical,
        first: { window_id: 101 },
        second: { window_id: 202 }
      }.freeze,
      active_window_id: 202,
      windows: [
        { id: 101, text: "first", point: { row: 0, col: 0 }, name: "first.rb", active: false },
        { id: 202, text: "second", point: { row: 0, col: 2 }, name: "second.rb", active: true }
      ].map(&:freeze).freeze
    )

    expect(view.editor_area).to be_a(QSplitter)
    expect(view.editor_area.count).to eq(2)
    expect(view.instance_variable_get(:@panes).length).to eq(2)
    expect(view.editor).to equal(view.instance_variable_get(:@panes).fetch(202).editor)
  end

  it "collapses back to the remaining Qt pane after a window is deleted" do
    view = described_class.new
    @views << view
    pane = { id: 101, text: "remaining", point: { row: 0, col: 0 }, name: "doc", active: true }
    view.render_layout(
      tree: { direction: :horizontal, first: { window_id: 101 }, second: { window_id: 202 } },
      active_window_id: 101,
      windows: [pane, pane.merge(id: 202, text: "closed", active: false)]
    )
    view.render_layout(
      tree: { window_id: 101 },
      active_window_id: 101,
      windows: [pane]
    )

    expect(view.editor_area).not_to be_a(QSplitter)
    expect(view.instance_variable_get(:@panes).keys).to eq([101])
  end
end
