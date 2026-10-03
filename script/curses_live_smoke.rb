#!/usr/bin/env ruby

require "fileutils"
require "io/wait"
require "pty"
require "tmpdir"

repository = File.expand_path("..", __dir__)
smoke_dir = Dir.mktmpdir("roded-curses-smoke.", "/tmp")
config_dir = File.join(smoke_dir, "config")
cache_dir = File.join(smoke_dir, "cache")
source_path = File.join(smoke_dir, "input.txt")
log_path = File.join(smoke_dir, "roded.log")
FileUtils.mkdir_p([config_dir, cache_dir])
File.write(source_path, "one\ntwo\nthree\n")

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
  [["\x0e", 0.8], ["\x18", 0.3], ["\x03", 0.3]].each do |key, delay|
    sleep delay
    writer.write(key)
  end

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
  'next_event: read_key: "C-n"',
  "publish_ui_update: move_cursor",
  'next_event: read_key: "C-x"',
  'next_event: read_key: "C-c"',
  "publish_ui_update: quit"
]
missing_entries = required_log_entries.reject { |entry| log.include?(entry) }
abort "curses smoke exited #{exit_status.inspect}; missing #{missing_entries.inspect}; files: #{smoke_dir}" unless
  exit_status&.zero? && missing_entries.empty? && !log.include?("Editor runtime failed")

puts "curses live smoke passed (C-n, C-x C-c); output=#{captured.bytesize} bytes; logs=#{smoke_dir}"
