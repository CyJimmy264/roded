require_relative "../lib/roded/frontends/qt"

RSpec.describe Roded::Frontends::QtEventLoop do
  it "releases the GVL for the native event loop while preserving QApplication lifecycle" do
    app = double("QApplication")
    allow(Qt::Native).to receive(:ensure_loaded!)
    expect(Qt::Bridge).to receive(:attach_function)
      .with(:qt_ruby_qapplication_exec, [:pointer], :int, blocking: true).ordered
    expect(app).to receive(:exec).ordered.and_return(0)
    expect(described_class.run(app)).to eq(0)
  end
end
