# frozen_string_literal: true

module Roded
  class MiniBuffer
    def get_command(prompt = "Команда: ")
      print prompt
      gets.chomp
    end

    # Для ввода имени файла и т.п.
    def get_input(prompt)
      print prompt
      gets.chomp
    end

    def display_message(message)
      puts "\n#{message}\n" # Вывод сообщения (например, об успехе сохранения)
    end
  end
end
