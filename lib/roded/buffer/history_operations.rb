module Roded
  # Replays and groups the undoable edit records owned by a buffer.
  module BufferHistoryOperations
    def undo # rubocop:disable Naming/PredicateMethod -- editor commands use imperative names
      return false if readonly || @undo_stack.empty?

      edits = @undo_stack.pop
      edits.reverse_each do |edit|
        apply_edit(edit, :before)
        notify_position_change(inverse_change(edit.position_change))
      end
      @redo_stack << edits
      notify_observers
      true
    end

    def redo # rubocop:disable Naming/PredicateMethod -- editor commands use imperative names
      return false if readonly || @redo_stack.empty?

      edits = @redo_stack.pop
      edits.each do |edit|
        apply_edit(edit, :after)
        notify_position_change(edit.position_change)
      end
      @undo_stack << edits
      notify_observers
      true
    end

    def with_undo_group
      @undo_group_depth += 1
      yield
    ensure
      @undo_group_depth -= 1
      if @undo_group_depth.zero? && !@undo_group_edits.empty?
        @undo_stack << @undo_group_edits
        @undo_group_edits = []
      end
    end

    private

    def inverse_change(change)
      return unless change

      Buffer::PositionChange.new(start: change.start, old_end: change.new_end, new_end: change.old_end)
    end
  end
end
