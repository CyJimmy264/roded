module Roded
  module Benchmarking
    # Runs the same command path while removing snapshot construction and delivery.
    class CoreApplication < Application
      def publish_ui_update(_update); end
    end
  end
end
