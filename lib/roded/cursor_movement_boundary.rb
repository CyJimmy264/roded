module Roded
  # Recognizes navigation that cannot change the point before touching editor state.
  class CursorMovementBoundary
    START_ACTIONS = %i[move_word_backward document_start].freeze
    END_ACTIONS = %i[move_word_forward document_end].freeze

    def self.call(type, window)
      return false unless window

      point = window.point
      case type
      when :move_up, :page_up then point[:row].zero?
      when :move_down, :page_down then point[:row] == window.buffer.lines.length - 1
      when :move_left, :line_start then point[:col].zero?
      when :move_right, :line_end then point[:col] == window.line_at_point.length
      else document_boundary?(type, point, window.buffer)
      end
    end

    def self.document_boundary?(type, point, buffer)
      return point[:row].zero? && point[:col].zero? if START_ACTIONS.include?(type)
      return false unless END_ACTIONS.include?(type)

      point[:row] == buffer.lines.length - 1 && point[:col] == buffer.lines.last.length
    end
    private_class_method :document_boundary?
  end
end
