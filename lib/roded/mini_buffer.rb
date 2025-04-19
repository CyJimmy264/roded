module Roded

  class MiniBuffer

    def initialize
      @observers = []
    end

    def add_observer(observer)
      @observers << observer unless @observers.include?(observer)
    end

    def remove_observer(observer)
      @observers.delete(observer)
    end

    def notify_observers
      @observers.each { |obs| obs.update(self) }
    end

    def get_command(prompt = "Команда: ")
      print prompt
      result = gets.chomp
      notify_observers
      result
    end

    # Для ввода имени файла и т.п.
    def get_input(prompt)
      print prompt
      result = gets.chomp
      notify_observers
      result
    end

    def display_message(message)
      puts "\n#{message}\n" # Вывод сообщения (например, об успехе сохранения)
      notify_observers
    end
  end
end
