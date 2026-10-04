module Roded
  # Publishes buffer content and position changes to registered views.
  module BufferObservationOperations
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
      @observers.each { |observer| observer.update(self) }
    end

    private

    def notify_position_change(change)
      return unless change

      @edit_observers.each { |observer| observer.buffer_edited(self, change) }
    end
  end
end
