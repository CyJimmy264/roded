module Roded

  # Main application class
  #
  # Creates all objects and dispatches commands from the user input through arbitrary platforms
  class Application
    def initialize
      @buffer = Buffer.new
      @curses_app = Frontends::Curses.new(@buffer)
      @window = Window.new(@buffer) if defined?(Window)
      @status_bar = StatusBar.new(@buffer) if defined?(StatusBar)
      @mini_buffer = MiniBuffer.new
    end

    def run
      loop do
        event = @curses_app.get_event
        break if event.type == :quit
        handle_event(event)
        @curses_app.render(@buffer)
      end
    end

    def handle_event(event)
      case event.type
      when :move_down
        @buffer.move_cursor_down
      when :move_up
        @buffer.move_cursor_up
      when :move_left
        @buffer.move_cursor_left
      when :move_right
        @buffer.move_cursor_right
      # Add more event handling as needed, using event.payload for additional data
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
