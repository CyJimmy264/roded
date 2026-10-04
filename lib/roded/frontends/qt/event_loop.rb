module Roded
  module Frontends
    # qt 0.2 attaches QApplication.exec without releasing Ruby's GVL.
    # Its native loop must let core/input/IPC threads run between GUI callbacks.
    class QtEventLoop
      def self.run(application)
        ::Qt::Native.ensure_loaded!
        ::Qt::Bridge.attach_function(:qt_ruby_qapplication_exec, [:pointer], :int, blocking: true)
        application.exec
      end
    end
  end
end
