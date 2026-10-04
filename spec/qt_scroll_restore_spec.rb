require "spec_helper"
require_relative "../lib/roded/frontends/qt"

RSpec.describe Roded::Frontends::QtEditorPane, "deferred viewport restoration" do
  before(:context) { @qt_application = QApplication.new(0, ["roded-scroll-restore-spec"]) }
  before do
    @parent = QWidget.new
    @pane = described_class.new(@parent)
    allow(@pane).to receive(:restore_pending_viewport).and_call_original
  end
  after do
    @parent.close
    QApplication.process_events
  end
  after(:context) { @qt_application.quit }

  it "runs one restoration per timer firing after repeated rendered frames" do
    20.times do
      @pane.send(:schedule_scroll_restore)
      3.times { QApplication.process_events }
    end

    expect(@pane).to have_received(:restore_pending_viewport).exactly(20).times
  end

  it "coalesces multiple requests while restoration is pending" do
    20.times { @pane.send(:schedule_scroll_restore) }
    3.times { QApplication.process_events }

    expect(@pane).to have_received(:restore_pending_viewport).once
  end
end
