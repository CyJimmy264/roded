require "spec_helper"
require_relative "../lib/roded/frontends/qt"

RSpec.shared_context "Qt horizontal scroll lifecycle" do
  before(:context) { @qt_application = QApplication.new(0, ["roded-horizontal-scroll-spec"]) }
  before do
    @view = described_class.new
    @feedback = []
    @view.on_horizontal_scroll { |payload| @feedback << payload }
    @snapshot = { text: (["abcdefghij " * 250] * 4).join("\n"),
                  point: { row: 0, col: 0 }, name: "long lines", active: true }
    @view.render(@snapshot)
    @view.show
    @view.window.resize(420, 240)
    3.times { QApplication.process_events }
    @feedback.clear
  end
  after do
    @view.close
    QApplication.process_events
  end
  after(:context) { @qt_application.quit }
end

RSpec.describe Roded::Frontends::QtEditorWindow, "native horizontal scrolling" do
  include_context "Qt horizontal scroll lifecycle"

  it "emits native scroll signals during rendering and reports only the settled origin to the core" do
    native_values = []
    @view.editor.horizontal_scroll_bar.connect("valueChanged(int)") { |value| native_values << value }

    @view.render(@snapshot.merge(point: { row: 0, col: 90 }))

    expect(native_values).not_to be_empty
    expect(@feedback).to be_empty
    3.times { QApplication.process_events }
    expect(@feedback.length).to eq(1)
    expect(@feedback.first[:left_column]).to be_positive
  end

  it "restores the requested visible origin without reporting intermediate native scroll changes" do
    native_values = []
    @view.editor.horizontal_scroll_bar.connect("valueChanged(int)") { |value| native_values << value }
    snapshot = @snapshot.merge(point: { row: 0, col: 90 }, left_column: 70)

    @view.render(snapshot)
    3.times { QApplication.process_events }

    expected = Roded::Frontends::QtCursorMapper.horizontal_offset(@view.editor, snapshot[:text], 0, 70, snapshot)
    expect(@view.editor.horizontal_scroll_bar.value).to eq(expected)
    expect(native_values).not_to be_empty
    expect(@feedback).to be_empty
  end
end
