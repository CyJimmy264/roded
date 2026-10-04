#!/usr/bin/env ruby

require "fileutils"
require "io/console"
require "io/wait"
require "pty"
require "timeout"
require "tmpdir"

def drain_output(reader, captured)
  loop { captured << reader.read_nonblock(65_536) }
rescue IO::WaitReadable, EOFError, Errno::EIO
  nil
end

def send_input(writer, reader, captured, bytes, delay: 0.1)
  writer.write(bytes)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + delay
  while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    drain_output(reader, captured)
    sleep 0.02
  end
end

def wait_for_exit(reader, captured, pid)
  Timeout.timeout(12) { poll_process_exit(reader, captured, pid) }
rescue Timeout::Error
  Process.kill("TERM", pid)
  Process.wait(pid)
  raise "curses scale process did not exit"
end

def poll_process_exit(reader, captured, pid)
  loop do
    drain_output(reader, captured)
    result = Process.waitpid2(pid, Process::WNOHANG)
    return result.last.exitstatus if result

    sleep 0.05
  end
end

def log_entry?(path, entry) = File.file?(path) && File.read(path).include?(entry)

def wait_for_log_entry(path, entry, reader, captured)
  Timeout.timeout(10) do
    loop do
      drain_output(reader, captured)
      return if log_entry?(path, entry)

      sleep 0.05
    end
  end
rescue Timeout::Error
  raise "curses scale smoke did not observe log entry: #{entry}"
end

repository = File.expand_path("..", __dir__)
smoke_dir = Dir.mktmpdir("roded-curses-scale.", "/tmp")
config_dir = File.join(smoke_dir, "config")
cache_dir = File.join(smoke_dir, "cache")
FileUtils.mkdir_p([config_dir, cache_dir])
source_path = File.join(smoke_dir, "large.txt")
source_text = "#{1.upto(10_000).map { |line| format("line %05d", line) }.join("\n")}\n"
File.binwrite(source_path, source_text)
buffer_paths = [source_path]
30.times do |index|
  path = File.join(smoke_dir, "buffer-#{index + 1}.txt")
  File.write(path, "buffer #{index + 1}\n")
  buffer_paths << path
end
log_path = File.join(smoke_dir, "roded.log")
environment = {
  "TERM" => "xterm-256color",
  "XDG_CONFIG_HOME" => config_dir,
  "XDG_CACHE_HOME" => cache_dir,
  "RODED_LOG_PATH" => log_path,
  "RODED_LOG_LEVEL" => "DEBUG"
}
captured = +""
exit_status = nil

PTY.spawn(environment, "bundle", "exec", "bin/roded", *buffer_paths, chdir: repository) do |reader, writer, pid|
  reader.winsize = [24, 80]
  sleep 1
  30.times { send_input(writer, reader, captured, "\x18\e[D") }
  send_input(writer, reader, captured, "\e>", delay: 0.4)
  send_input(writer, reader, captured, "\x18\x13", delay: 0.5)
  reader.winsize = [12, 50]
  Process.kill("WINCH", pid)
  sleep 0.2
  send_input(writer, reader, captured, "\x0e", delay: 0.4)
  send_input(writer, reader, captured, "\x03rr", delay: 0.5)
  send_input(writer, reader, captured, "loop { sleep 0.01 }", delay: 0.3)
  send_input(writer, reader, captured, "\x03\x03", delay: 0.3)
  send_input(writer, reader, captured, "\x03\x0b", delay: 0.2)
  wait_for_log_entry(
    log_path, 'event received: repl_result {stdout: "", stderr: "", error: "Interrupt"}', reader, captured
  )
  send_input(writer, reader, captured, "1 + 1", delay: 0.2)
  send_input(writer, reader, captured, "\x03\x03", delay: 0.2)
  wait_for_log_entry(log_path, 'event received: repl_result {stdout: "", stderr: "", result: "2"}', reader, captured)
  send_input(writer, reader, captured, "\x18\x03", delay: 0.3)
  send_input(writer, reader, captured, "d\r", delay: 0.4)
  exit_status = wait_for_exit(reader, captured, pid)
end

log = File.read(log_path)
switch_count = log.scan('next_event: read_key: "Left"').length
File.binwrite(File.join(smoke_dir, "curses-output.ansi"), captured)
required_events = [
  'next_event: read_key: "M->"', 'next_event: read_key: "C-n"',
  'event received: repl_result {stdout: "", stderr: "", error: "Interrupt"}',
  'event received: repl_result {stdout: "", stderr: "", result: "2"}',
  "event received: resize", "publish_ui_update: quit"
]
missing = required_events.reject { |entry| log.include?(entry) }
# Ncurses can retain the leading "1" from "1:1" and transmit only the changed "0001:1" suffix.
rendered_end = captured.include?("10001:1") || captured.include?("0001:1")
unless exit_status&.zero? && switch_count >= 30 && missing.empty? && rendered_end
  abort "curses scale smoke failed: exit=#{exit_status.inspect}, switches=#{switch_count}, " \
        "missing=#{missing.inspect}, rendered_end=#{rendered_end}; files=#{smoke_dir}"
end

abort "curses scale smoke changed the 10,000-line file" unless File.binread(source_path) == source_text

puts "curses scale smoke passed: 10,000 lines, 31 buffers, 30 buffer switches, " \
     "document end, save, PTY resize, redraw and live REPL interrupt/recovery; log=#{log_path}"
