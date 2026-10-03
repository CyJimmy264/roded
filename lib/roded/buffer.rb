require_relative "buffer/serialization_operations"
require_relative "buffer/observation_operations"
require_relative "buffer/cursor_operations"
require_relative "buffer/character_edit_operations"
require_relative "buffer/line_edit_operations"
require_relative "buffer/region_operations"
require_relative "buffer/history_operations"
require_relative "buffer/edit_recording_operations"
require_relative "buffer/position_change_operations"

module Roded
  # A text document with controlled edits, cursor movement, and edit history.
  class Buffer
    PositionChange = Data.define(:start, :old_end, :new_end)
    Edit = Struct.new(
      :row, :before_lines, :after_lines, :before_cursor, :after_cursor,
      :before_line_ending, :after_line_ending, :before_final_newline, :after_final_newline,
      :position_change, keyword_init: true
    )

    include BufferSerializationOperations
    include BufferObservationOperations
    include BufferCursorOperations
    include BufferCharacterEditOperations
    include BufferLineEditOperations
    include BufferRegionOperations
    include BufferHistoryOperations
    include BufferEditRecordingOperations
    include BufferPositionChangeOperations

    attr_accessor :filename, :readonly, :file_revision, :major_mode
    attr_reader :line_ending, :final_newline, :name

    def initialize(name = nil)
      @name = name
      initialize_document_state
      initialize_history_state
      @observers = []
      @edit_observers = []
      @readonly = false
      @saved_text = to_s
    end

    def mode
      major_mode || SyntaxHighlighter.new.mode_for(filename || name)
    end

    private

    def initialize_document_state
      @filename = nil
      @major_mode = nil
      @file_revision = nil
      @lines = [String.new("")]
      @cursor_pos = { row: 0, col: 0 }
      @line_ending = "\n"
      @final_newline = false
    end

    def initialize_history_state
      @undo_stack = []
      @redo_stack = []
      @undo_group_depth = 0
      @undo_group_edits = []
    end
  end
end
