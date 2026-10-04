module Roded
  module Benchmarking
    # Hooks keep setup, action, and behavioral verification separate from timing.
    Scenario = Data.define(:name, :prepare, :action, :verify)
  end
end
