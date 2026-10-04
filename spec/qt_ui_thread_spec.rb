require "timeout"
require "qt"
require "spec_helper"
require_relative "../lib/roded/frontends/qt"

module QtUiThreadSpecHelpers
  # Records which thread applied a dispatcher callback.
  class Recorder
    attr_reader :threads, :messages

    def initialize
      @threads = Queue.new
      @messages = []
    end

    def display_message(message)
      @messages << message
      record_thread
    end

    def close = record_thread

    def quit = record_thread

    private

    def record_thread
      @threads << Thread.current
    end
  end
end

RSpec.configure do |config|
  config.before(:suite) { QApplication.new(0, ["roded-ui-thread-spec"]) }
end

RSpec.describe Roded::Frontends::QtUiDispatcher, "GUI thread delivery" do
  it "applies worker-thread messages and shutdown on the Qt thread" do
    gui_thread = Thread.current
    recorder = QtUiThreadSpecHelpers::Recorder.new
    dispatcher = described_class.new(recorder, recorder, Object.new)
    dispatcher.start
    producer = Thread.new do
      dispatcher.post(:message, "from core")
      dispatcher.post(:quit)
    end
    producer.join
    Timeout.timeout(2) do
      while recorder.threads.size < 3
        QApplication.process_events
        sleep 0.01
      end
    end

    expect(3.times.map { recorder.threads.pop }).to all(equal(gui_thread))
    expect(recorder.messages).to eq(["from core"])
  ensure
    producer&.join(1)
    dispatcher&.stop
  end
end

module QtCoreFailureShutdownSpecHelpers
  def run_failing_core(application, frontend)
    application.register_command("raise-in-core", binding: "C-c z") { raise "simulated core failure" }
    input_queue = frontend.instance_variable_get(:@input_queue)
    %w[C-c z].each { |key| input_queue << Roded::Event.new(:key, { key: }) }
    errors = Queue.new
    runtime_thread = Thread.new do
      application.run(manage_signals: false)
    rescue StandardError => e
      errors << e
    end
    [runtime_thread, errors]
  end

  def process_qt_until_closed(runtime_thread, frontend)
    Timeout.timeout(3) do
      while runtime_thread.alive? || frontend.view.window.is_visible
        QApplication.process_events
        sleep 0.01
      end
    end
  end
end

RSpec.describe "Qt core failure shutdown" do
  include QtCoreFailureShutdownSpecHelpers

  it "closes the real window through the GUI timer without hanging" do
    application = Roded::Application.new
    application.startup
    frontend = Roded::Frontends::Qt.new(application)
    application.add_frontend(frontend)
    frontend.view.show
    QApplication.process_events
    runtime_thread, errors = run_failing_core(application, frontend)
    process_qt_until_closed(runtime_thread, frontend)

    expect(Timeout.timeout(1) { errors.pop }).to have_attributes(message: "simulated core failure")
    expect(frontend.view.window.is_visible).to be(false)
  ensure
    application&.push_event(Roded::Event.new(:quit, {})) if runtime_thread&.alive?
    runtime_thread&.join(1)
    frontend&.instance_variable_get(:@ui_dispatcher)&.stop
    frontend&.view&.close
  end
end
