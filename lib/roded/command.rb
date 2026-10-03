module Roded
  # Keeps frontend messages independent from later core mutations.
  module UIUpdatePayload
    module_function

    def copy(value)
      return value if deeply_frozen?(value)
      return value.dup.freeze if value.is_a?(String)
      return copy_hash(value) if value.is_a?(Hash)
      return copy_array(value) if value.is_a?(Array)
      return value if immutable_scalar?(value)

      raise TypeError, "unsupported mutable UI update value: #{value.class}"
    end

    def deeply_frozen?(value)
      return immutable_scalar?(value) if scalar?(value)
      return false unless value.frozen?
      return deeply_frozen_hash?(value) if value.is_a?(Hash)
      return deeply_frozen_array?(value) if value.is_a?(Array)

      value.is_a?(String)
    end

    def copy_hash(value)
      value.each_with_object({}) do |(key, child), snapshot|
        snapshot[copy(key)] = copy(child)
      end.freeze
    end

    def copy_array(value)
      value.map { |child| copy(child) }.freeze
    end

    def deeply_frozen_hash?(value)
      value.all? { |key, child| deeply_frozen?(key) && deeply_frozen?(child) }
    end

    def deeply_frozen_array?(value)
      value.all? { |child| deeply_frozen?(child) }
    end

    def scalar?(value)
      value.nil? || value.equal?(true) || value.equal?(false) || value.is_a?(Numeric) || value.is_a?(Symbol)
    end

    def immutable_scalar?(value)
      scalar?(value) && value.frozen?
    end
  end

  UIUpdate = Data.define(:type, :payload) do
    def initialize(type:, payload:)
      super(type: type, payload: UIUpdatePayload.copy(payload))
    end
  end

  private_constant :UIUpdatePayload

  # Compatibility name for frontend adapters during the UI update migration.
  Command = UIUpdate
end
