module Roded
  UIUpdate = Data.define(:type, :payload)

  # Compatibility name for frontend adapters during the UI update migration.
  Command = UIUpdate
end
