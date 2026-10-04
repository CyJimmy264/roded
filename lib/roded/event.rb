module Roded
  InputEvent = Data.define(:type, :payload)
  EditorCommand = Data.define(:type, :payload, :source_id, :view_id)

  # Compatibility name for frontends and runtime events while callers migrate.
  Event = InputEvent
end
