#!/usr/bin/env ruby

require "fileutils"
require "io/wait"
require "pty"
require "tmpdir"

def drain_pty_output(reader, captured)
  loop do
    captured << reader.read_nonblock(65_536)
  rescue IO::WaitReadable, EOFError, Errno::EIO
    break
  end
end

def send_terminal_input(writer, reader, captured, bytes, delay)
  writer.write(bytes)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + delay
  while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    drain_pty_output(reader, captured)
    sleep 0.05
  end
end

def wait_for_file_text(path, expected, reader, captured)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
  loop do
    return if File.binread(path) == expected

    drain_pty_output(reader, captured)
    if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      raise "file did not reach #{expected.inspect}: #{path}"
    end

    sleep 0.05
  end
end

def send_smoke_input(session, bytes, delay)
  send_terminal_input(session.fetch(:writer), session.fetch(:reader), session.fetch(:captured), bytes, delay)
end

def save_smoke_buffer(session, expected)
  send_smoke_input(session, "\x18", 0.3)
  send_smoke_input(session, "\x13", 0.8)
  wait_for_file_text(session.fetch(:source_path), expected, session.fetch(:reader), session.fetch(:captured))
  session[:saved_text] = expected
end

def exercise_typing_undo_redo(session)
  send_smoke_input(session, "XYZ", 0.4)
  save_smoke_buffer(session, session.fetch(:edited_text))
  exercise_undo_redo(session, "\x1f")
  exercise_undo_redo(session, "\x18u")
  send_smoke_input(session, "\e[18~", 0.4)
  wait_for_file_text(
    session.fetch(:source_path), session.fetch(:edited_text), session.fetch(:reader), session.fetch(:captured)
  )
end

def exercise_undo_redo(session, undo_keys)
  send_smoke_input(session, undo_keys, 0.4)
  save_smoke_buffer(session, session.fetch(:original_text))
  send_smoke_input(session, "\x03rd", 0.4)
  save_smoke_buffer(session, session.fetch(:edited_text))
end

def exercise_paste_undo_redo(session)
  pasted_text = "one\nXYZA\nBtwo\nthree\n"
  send_smoke_input(session, "\e[200~A\nB\e[201~", 0.5)
  save_smoke_buffer(session, pasted_text)
  send_smoke_input(session, "\x1f", 0.4)
  save_smoke_buffer(session, session.fetch(:edited_text))
  send_smoke_input(session, "\x03rd", 0.4)
  save_smoke_buffer(session, pasted_text)
end

def exercise_curses_undo_redo(session)
  send_smoke_input(session, "\e>", 0.4)
  send_smoke_input(session, "\e<", 0.4)
  send_smoke_input(session, "\x0e", 0.8)
  exercise_typing_undo_redo(session)
  exercise_paste_undo_redo(session)
  exercise_curses_close_cancel(session)
end

def exercise_curses_close_cancel(session)
  saved_text = session.fetch(:saved_text)
  send_smoke_input(session, "Q", 0.3)
  send_quit_sequence(session)
  send_smoke_input(session, "c\r", 0.5)
  wait_for_file_text(session.fetch(:source_path), saved_text, session.fetch(:reader), session.fetch(:captured))
  send_smoke_input(session, "\x1f", 0.4)
  wait_for_file_text(session.fetch(:source_path), saved_text, session.fetch(:reader), session.fetch(:captured))
  send_quit_sequence(session)
end

def send_quit_sequence(session)
  send_smoke_input(session, "\x18", 0.3)
  send_smoke_input(session, "\x03", 0.3)
end

repository = File.expand_path("..", __dir__)
smoke_dir = Dir.mktmpdir("roded-curses-smoke.", "/tmp")
config_dir = File.join(smoke_dir, "config")
cache_dir = File.join(smoke_dir, "cache")
source_path = File.join(smoke_dir, "input.txt")
log_path = File.join(smoke_dir, "roded.log")
FileUtils.mkdir_p([config_dir, cache_dir])
original_text = "one\ntwo\nthree\n"
edited_text = "one\nXYZtwo\nthree\n"
File.write(source_path, original_text)

environment = {
  "TERM" => "xterm-256color",
  "XDG_CONFIG_HOME" => config_dir,
  "XDG_CACHE_HOME" => cache_dir,
  "RODED_LOG_PATH" => log_path,
  "RODED_LOG_LEVEL" => "DEBUG"
}
captured = +""
exit_status = nil

PTY.spawn(environment, "bundle", "exec", "bin/roded", source_path, chdir: repository) do |reader, writer, pid|
  session = { writer:, reader:, captured:, source_path:, original_text:, edited_text: }
  sleep 1
  exercise_curses_undo_redo(session)

  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
  loop do
    if reader.wait_readable(0.1)
      begin
        captured << reader.read_nonblock(65_536)
      rescue IO::WaitReadable, EOFError, Errno::EIO
        nil
      end
    end
    result = Process.waitpid2(pid, Process::WNOHANG)
    if result
      exit_status = result.last.exitstatus
      break
    end
    next if Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline

    Process.kill("TERM", pid)
    Process.wait(pid)
    abort "curses process did not exit after C-x C-c; smoke files: #{smoke_dir}"
  end
end

log = File.read(log_path)
required_log_entries = [
  'next_event: read_key: "M->"',
  'next_event: read_key: "M-<"',
  'next_event: read_key: "C-n"',
  "publish_ui_update: move_cursor",
  'next_event: read_key: "C-_"',
  'next_event: read_key: "F7"',
  "event received: paste",
  'next_event: read_key: "C-c"',
  'next_event: read_key: "r"',
  'next_event: read_key: "d"',
  'next_event: read_key: "C-x"',
  'next_event: read_key: "u"',
  "publish_ui_update: quit"
]
missing_entries = required_log_entries.reject { |entry| log.include?(entry) }
abort "curses smoke exited #{exit_status.inspect}; missing #{missing_entries.inspect}; files: #{smoke_dir}" unless
  exit_status&.zero? && missing_entries.empty? && !log.include?("Editor runtime failed")

puts "curses live smoke passed (M-</M->, C-n, typing, bracketed paste, C-_, C-x u, C-c r d, F7 save, quit cancel); " \
     "output=#{captured.bytesize} bytes; logs=#{smoke_dir}"
