module Roded
  # Roded::Buffer - Buffer class for the Roded text editor
  #
  # A Buffer is a container for text. It is the primary data structure
  # used by the Roded text editor. It provides ways to manipulate the
  # text, such as inserting and deleting characters, and allows other
  # objects to observe its state.
  class Buffer
    PositionChange = Data.define(:start, :old_end, :new_end)
    Edit = Struct.new(
      :row, :before_lines, :after_lines, :before_cursor, :after_cursor,
      :before_line_ending, :after_line_ending, :before_final_newline, :after_final_newline,
      :position_change, keyword_init: true
    )

    attr_accessor :filename, :readonly, :file_revision
    attr_reader :line_ending, :final_newline, :name

    def initialize(name = nil)
      @name = name
      @filename = nil
      @file_revision = nil
      @lines = [String.new("")]
      @cursor_pos = { row: 0, col: 0 }
      @line_ending = "\n"
      @final_newline = false
      @observers = []
      @edit_observers = []
      @readonly = false
      @saved_text = to_s
      @undo_stack = []
      @redo_stack = []
      @undo_group_depth = 0
      @undo_group_edits = []
    end

    def lines=(lines)
      return if readonly

      new_lines = Array(lines).map(&:to_s)
      new_lines = [""] if new_lines.empty?
      record_edit(0, @lines.length, new_lines.length) do
        @lines = new_lines
        clamp_cursor
      end
    end

    def load_text(text)
      validate_text!(text)
      @line_ending = text.scan(/\r\n|\n/).uniq.first || "\n"
      @final_newline = text.end_with?("\n")
      @lines = text.gsub("\r\n", "\n").split("\n", -1).tap { |lines| lines.pop if @final_newline }
      @lines = [""] if @lines.empty?
      @cursor_pos = { row: 0, col: 0 }
      @undo_stack.clear
      @redo_stack.clear
      @undo_group_edits.clear
      mark_saved
      self
    end

    def cursor_pos=(position)
      @cursor_pos = { row: position.fetch(:row, 0).to_i, col: position.fetch(:col, 0).to_i }
      clamp_cursor
    end

    def lines
      @lines.map { |line| line.dup.freeze }.freeze
    end

    def cursor_pos
      @cursor_pos.dup.freeze
    end

    def add_observer(observer)
      @observers << observer unless @observers.include?(observer)
    end

    def remove_observer(observer)
      @observers.delete(observer)
    end

    def add_edit_observer(observer)
      @edit_observers << observer unless @edit_observers.include?(observer)
    end

    def remove_edit_observer(observer)
      @edit_observers.delete(observer)
    end

    def notify_observers
      @observers.each { |obs| obs.update(self) }
    end

    def insert_char(char)
      return if readonly
      return if char.nil? || char.empty?

      row = @cursor_pos[:row]
      record_edit(row, 1, 1) do
        line = @lines[row]
        @lines[row] = line.dup.insert(@cursor_pos[:col], char)
        @cursor_pos[:col] = [@cursor_pos[:col] + char.length, line_at_cursor.length].min
      end
    end

    def insert_text(text)
      return if readonly
      return if text.nil? || text.empty?
      raise ArgumentError, "text must be valid UTF-8" unless text.encoding == Encoding::UTF_8 && text.valid_encoding?

      row, inserted_lines, cursor_col = paste_snapshot(text)

      record_edit(row, 1, inserted_lines.length) do
        @lines[row, 1] = inserted_lines
        @cursor_pos = { row: row + inserted_lines.length - 1, col: cursor_col }
      end
    end

    def backspace
      return if readonly

      if @cursor_pos[:col].positive?
        row = @cursor_pos[:row]
        record_edit(row, 1, 1) do
          line = @lines[row].dup
          line.slice!(@cursor_pos[:col] - 1)
          @lines[row] = line
          @cursor_pos[:col] = [@cursor_pos[:col] - 1, 0].max
        end
      elsif @cursor_pos[:row].positive? # Backspace at start of line should join previous
        row = @cursor_pos[:row] - 1
        record_edit(row, 2, 1) do
          previous_line = @lines[row]
          @lines[row] = previous_line + @lines[row + 1]
          @lines.delete_at(row + 1)
          @cursor_pos = { row:, col: previous_line.length }
        end
      end
    end

    def delete_char
      return if readonly

      line = @lines[@cursor_pos[:row]]
      if @cursor_pos[:col] < line.length
        row = @cursor_pos[:row]
        record_edit(row, 1, 1) do
          edited_line = @lines[row].dup
          edited_line.slice!(@cursor_pos[:col])
          @lines[row] = edited_line
        end
      elsif @cursor_pos[:row] < @lines.length - 1
        row = @cursor_pos[:row]
        record_edit(row, 2, 1) do
          @lines[row] = line + @lines[row + 1]
          @lines.delete_at(row + 1)
        end
      end
    end

    def kill_line(kill_ring)
      return if readonly

      line = @lines[@cursor_pos[:row]]
      if @cursor_pos[:col] < line.length
        killed = line[@cursor_pos[:col]..]
        row = @cursor_pos[:row]
        record_edit(row, 1, 1) do
          kill_ring.push(killed)
          @lines[row] = line[0...@cursor_pos[:col]]
        end
      elsif @cursor_pos[:row] < @lines.length - 1
        row = @cursor_pos[:row]
        record_edit(row, 2, 1) do
          kill_ring.push("\n")
          @lines[row] = line + @lines[row + 1]
          @lines.delete_at(row + 1)
        end
      elsif @final_newline
        row = @cursor_pos[:row]
        record_edit(row, 1, 1) do
          kill_ring.push("\n")
          @final_newline = false
        end
      end
    end

    def region_text(start_position, end_position)
      start_position, end_position = ordered_positions(start_position, end_position)
      return "" if start_position == end_position

      first_row, first_col = start_position.values_at(:row, :col)
      last_row, last_col = end_position.values_at(:row, :col)
      return @lines[first_row][first_col...last_col].to_s if first_row == last_row

      segments = [@lines[first_row][first_col..].to_s]
      segments.concat(@lines[(first_row + 1)...last_row])
      segments << @lines[last_row][0...last_col].to_s
      segments.join(@line_ending)
    end

    def delete_region(start_position, end_position)
      return false if readonly

      start_position, end_position = ordered_positions(start_position, end_position)
      return false if start_position == end_position

      first_row, first_col = start_position.values_at(:row, :col)
      last_row, last_col = end_position.values_at(:row, :col)
      record_edit(first_row, last_row - first_row + 1, 1) do
        prefix = @lines[first_row][0...first_col]
        suffix = @lines[last_row][last_col..].to_s
        @lines[first_row..last_row] = [prefix + suffix]
        @cursor_pos = { row: first_row, col: first_col }
      end
      true
    end

    def move_cursor_left
      @cursor_pos[:col] = [@cursor_pos[:col] - 1, 0].max
      notify_observers
    end

    def move_cursor_right
      @cursor_pos[:col] = [@cursor_pos[:col] + 1, line_at_cursor.length].min
      notify_observers
    end

    def move_cursor_line_start
      @cursor_pos[:col] = 0
      notify_observers
    end

    def move_cursor_line_end
      line = line_at_cursor || ""
      @cursor_pos[:col] = line.length
      notify_observers
    end

    def move_cursor_up
      @cursor_pos[:row] = [@cursor_pos[:row] - 1, 0].max
      clamp_cursor_col
      notify_observers
    end

    def move_cursor_down
      @cursor_pos[:row] = [@cursor_pos[:row] + 1, @lines.length - 1].min
      clamp_cursor_col
      notify_observers
    end

    def move_cursor_page_up(page_size)
      move_cursor_by_page(-page_size.to_i)
    end

    def move_cursor_page_down(page_size)
      move_cursor_by_page(page_size.to_i)
    end

    def to_s
      text = @lines.join(@line_ending)
      @final_newline ? text + @line_ending : text
    end

    def modified?
      to_s != @saved_text
    end

    def undo
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

    def redo
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

    def mark_saved
      @saved_text = to_s
    end

    def final_newline=(value)
      return if readonly

      record_edit(0, @lines.length, @lines.length) { @final_newline = !!value }
    end

    def line_ending=(value)
      raise ArgumentError, "unsupported line ending" unless ["\n", "\r\n"].include?(value)

      return if readonly

      record_edit(0, @lines.length, @lines.length) { @line_ending = value }
    end

    def line_at_cursor
      @lines[@cursor_pos[:row]].dup.freeze
    end

    def cursor_row
      @cursor_pos[:row]
    end

    def cursor_col
      @cursor_pos[:col]
    end

    def newline
      return if readonly

      row = @cursor_pos[:row]
      record_edit(row, 1, 2) do
        line = @lines[row]
        before = line[0...@cursor_pos[:col]]
        after = line[@cursor_pos[:col]..] || ""
        @lines[row] = before
        @lines.insert(row + 1, after)
        @cursor_pos = { row: row + 1, col: 0 }
      end
    end

  private

    def record_edit(row, before_count, after_count)
      before = edit_snapshot(row, before_count)
      yield
      after = edit_snapshot(row, after_count)
      return if before == after

      edit = Edit.new(
        row:, before_lines: before.fetch(:lines), after_lines: after.fetch(:lines),
        before_cursor: before.fetch(:cursor), after_cursor: after.fetch(:cursor),
        before_line_ending: before.fetch(:line_ending), after_line_ending: after.fetch(:line_ending),
        before_final_newline: before.fetch(:final_newline), after_final_newline: after.fetch(:final_newline),
        position_change: position_change(row, before.fetch(:lines), after.fetch(:lines))
      )
      @undo_group_depth.positive? ? @undo_group_edits << edit : @undo_stack << [edit]
      @redo_stack.clear
      notify_position_change(edit.position_change)
      notify_observers
    end

    def edit_snapshot(row, line_count)
      {
        lines: @lines.slice(row, line_count).map(&:dup), cursor: @cursor_pos.dup,
        line_ending: @line_ending.dup, final_newline: @final_newline
      }
    end

    def ordered_positions(first, second)
      positions = [first, second].map do |position|
        row = position.fetch(:row, 0).to_i.clamp(0, @lines.length - 1)
        col = position.fetch(:col, 0).to_i.clamp(0, @lines[row].length)
        { row:, col: }
      end
      positions.sort_by { |position| [position[:row], position[:col]] }
    end

    def paste_snapshot(text)
      row = @cursor_pos[:row]
      segments = text.gsub("\r\n", "\n").split("\n", -1)
      before = line_at_cursor[0...@cursor_pos[:col]]
      after = line_at_cursor[@cursor_pos[:col]..] || ""
      lines = segments.each_with_index.map do |segment, index|
        paste_line(segment, index, segments.length, before, after)
      end
      [row, lines, segments.last.length]
    end

    def paste_line(segment, index, count, before, after)
      prefix = index.zero? ? before : ""
      suffix = index == count - 1 ? after : ""
      prefix + segment + suffix
    end

    def apply_edit(edit, direction)
      previous = direction == :before
      source_lines = previous ? edit.after_lines : edit.before_lines
      target_lines = previous ? edit.before_lines : edit.after_lines
      @lines[edit.row, source_lines.length] = target_lines.map(&:dup)
      @cursor_pos = (previous ? edit.before_cursor : edit.after_cursor).dup
      @line_ending = (previous ? edit.before_line_ending : edit.after_line_ending).dup
      @final_newline = previous ? edit.before_final_newline : edit.after_final_newline
      clamp_cursor
    end

    def position_change(row, before_lines, after_lines)
      before_text = before_lines.join("\n")
      after_text = after_lines.join("\n")
      before_chars = before_text.each_char.to_a
      after_chars = after_text.each_char.to_a
      prefix = common_prefix_length(before_chars, after_chars)
      suffix = common_suffix_length(before_chars, after_chars, prefix)
      return if prefix == before_chars.length && prefix == after_chars.length

      before_end = before_chars.length - suffix
      after_end = after_chars.length - suffix
      PositionChange.new(
        start: position_at_offset(row, before_chars, prefix),
        old_end: position_at_offset(row, before_chars, before_end),
        new_end: position_at_offset(row, after_chars, after_end)
      )
    end

    def common_prefix_length(before_chars, after_chars)
      index = 0
      index += 1 while index < before_chars.length && index < after_chars.length &&
                        before_chars[index] == after_chars[index]
      index
    end

    def common_suffix_length(before_chars, after_chars, prefix)
      suffix = 0
      while suffix < before_chars.length - prefix && suffix < after_chars.length - prefix &&
            before_chars[-suffix - 1] == after_chars[-suffix - 1]
        suffix += 1
      end
      suffix
    end

    def position_at_offset(base_row, chars, offset)
      preceding = chars.take(offset).join
      parts = preceding.split("\n", -1)
      parts = [""] if parts.empty?
      { row: base_row + parts.length - 1, col: parts.last.length }.freeze
    end

    def inverse_change(change)
      return unless change

      PositionChange.new(start: change.start, old_end: change.new_end, new_end: change.old_end)
    end

    def notify_position_change(change)
      return unless change

      @edit_observers.each { |observer| observer.buffer_edited(self, change) }
    end

    def move_cursor_by_page(delta)
      @cursor_pos[:row] = [@cursor_pos[:row] + delta, 0].max
      @cursor_pos[:row] = [@cursor_pos[:row], @lines.length - 1].min
      clamp_cursor_col
      notify_observers
    end

    def clamp_cursor_col
      @cursor_pos[:col] = [@cursor_pos[:col], line_at_cursor.length].min
    end

    def clamp_cursor
      @cursor_pos[:row] = @cursor_pos[:row].to_i.clamp(0, @lines.length - 1)
      clamp_cursor_col
    end

    def validate_text!(text)
      raise ArgumentError, "text must be valid UTF-8" unless text.encoding == Encoding::UTF_8 && text.valid_encoding?
      raise ArgumentError, "mixed line endings are not supported" if text.scan(/\r\n|\n/).uniq.length > 1
    end
  end
end
