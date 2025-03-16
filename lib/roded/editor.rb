# frozen_string_literal: true

module Roded
  class Editor
    def initialize
      @buffer = Buffer.new
      @window = Window.new(@buffer)
      @status_bar = StatusBar.new(@buffer)
      @mini_buffer = MiniBuffer.new
    end

    def run
      @curses_app = CursesApp.new
      loop do
        break

        @window.display # Отображаем окно (буфер)
        @status_bar.display # Отображаем строку состояния

        command = @mini_buffer.get_command("M-x ") # Запрос команды (M-x аналог)
        process_command(command)

        # TODO: Обработка обычного ввода текста (не команд)
        # Пока просто для теста:
        char = $stdin.getch # Для посимвольного ввода (может потребоваться gem 'io-console' или аналог)
        @buffer.insert_char(char)
        break
      end
    end

    def process_command(command)
      case command
      when "open"
        filename = @mini_buffer.get_input("Открыть файл: ")
        open_file(filename)
      when "save"
        filename = @mini_buffer.get_input("Сохранить файл как: ")
        save_file(filename)
      when "quit"
        puts "Выход из Ruby Emacs."
        exit
      when "" # Пустая команда - просто обновить экран
        # Ничего не делаем, цикл просто обновит отображение
      else
        @mini_buffer.display_message("Неизвестная команда: #{command}")
      end
    end

    def open_file(filename)
      content = File.read(filename)
      @buffer.lines = content.lines.map(&:chomp) # Чтение файла построчно
      @buffer.filename = filename
      @mini_buffer.display_message("Файл '#{filename}' открыт.")
    rescue Errno::ENOENT
      @mini_buffer.display_message("Файл не найден: #{filename}")
    rescue StandardError => e
      @mini_buffer.display_message("Ошибка при открытии файла: #{e.message}")
    end

    def save_file(filename)
      File.write(filename, @buffer.to_s)
      @buffer.filename = filename # Обновляем имя файла в буфере
      @mini_buffer.display_message("Файл '#{filename}' сохранен.")
    rescue StandardError => e
      @mini_buffer.display_message("Ошибка при сохранении файла: #{e.message}")
    end
  end
end
