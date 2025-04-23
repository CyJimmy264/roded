module Roded
  # Main application class
  #
  # Creates all objects and dispatches commands from the user input through
  # arbitrary platforms
  class Application
    def initialize
      @buffers = Concurrent::Array.new
      @windows = Concurrent::Array.new
      @frontends = Concurrent::Array.new
      @frontend_futures = Concurrent::Array.new
      @event_channel = Concurrent::Channel.new
      @status_bar = nil
      @mini_buffer = nil
    end

    def welcome
      welcome_buffer = Buffer.new("Welcome")
      welcome_buffer.lines = [
        "Welcome to Roded!",
        "",
        "Press any key to get started.",
        "",
        "This is a read-only welcome buffer."
      ]
      welcome_buffer.readonly = true
      add_buffer(welcome_buffer)
      add_window(Window.new(welcome_buffer))
    end

    def add_buffer(buffer)
      @buffers << buffer
    end

    def add_window(window)
      @windows << window
    end

    def set_status_bar(status_bar)
      @status_bar = status_bar
    end

    def set_mini_buffer(mini_buffer)
      @mini_buffer = mini_buffer
    end

    def add_frontend(frontend)
      @frontends << frontend
      future = Concurrent::Future.execute do
        until @event_channel.closed?
          begin
            @event_channel << frontend.get_event
          rescue StandardError => e
            warn "Frontend thread error: #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
            break
          end
        end
      end
      @frontend_futures << future
    end

    def broadcast_command(command)
      @frontends.each { |f| f.handle_command(command) }
    end

    def run
      until @event_channel.closed?
        event = @event_channel.take
        if event.type == :quit
          @event_channel.close
        end
        handle_event(event)
      end

      @frontend_futures.each(&:wait)
    end

    def handle_event(event)
      case event.type
      when :move_down
        @buffers.first&.move_cursor_down
        broadcast_command(Command.new(:move_cursor, { direction: :down }))
      when :move_up
        @buffers.first&.move_cursor_up
        broadcast_command(Command.new(:move_cursor, { direction: :up }))
      when :move_left
        @buffers.first&.move_cursor_left
        broadcast_command(Command.new(:move_cursor, { direction: :left }))
      when :move_right
        @buffers.first&.move_cursor_right
        broadcast_command(Command.new(:move_cursor, { direction: :right }))
      when :render
        broadcast_command(Command.new(:render, {}))
      when :quit
        puts "handle_event: broadcast quit"
        broadcast_command(Command.new(:quit, {}))
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
      @buffers.first.lines = content.lines.map(&:chomp)
      @buffers.first.filename = filename
      @mini_buffer.display_message("Файл '#{filename}' открыт.")
    rescue Errno::ENOENT
      @mini_buffer.display_message("Файл не найден: #{filename}")
    rescue StandardError => e
      @mini_buffer.display_message("Ошибка при открытии файла: #{e.message}")
    end

    def save_file(filename)
      File.write(filename, @buffers.first.to_s)
      @buffers.first.filename = filename
      @mini_buffer.display_message("Файл '#{filename}' сохранен.")
    rescue StandardError => e
      @mini_buffer.display_message("Ошибка при сохранении файла: #{e.message}")
    end
  end
end
