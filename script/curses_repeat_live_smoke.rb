#!/usr/bin/env ruby

require "io/console"
require "io/wait"
require "pty"
require "timeout"
require "tmpdir"

# Inspect real ncurses output through a private PTY; no desktop terminal is used.
def drain_repeat_output(session)
  loop { session[:captured] << session[:reader].read_nonblock(65_536) }
rescue IO::WaitReadable, EOFError, Errno::EIO
  nil
end

def repeat_log(session)
  File.file?(session[:log_path]) ? File.read(session[:log_path]) : ""
end

def wait_for_repeat_log(session)
  Timeout.timeout(10) do
    loop do
      drain_repeat_output(session)
      log = repeat_log(session)
      return log if yield(log)

      sleep 0.01
    end
  end
end

def settle_repeat_output(session)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.15
  while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    drain_repeat_output(session)
    sleep 0.01
  end
end

def repeat_boundary_count(log)
  log.scan("cursor movement at boundary: move_up").length
end

def exercise_repeat_scroll(session)
  session[:writer].write("\egg200\r")
  wait_for_repeat_log(session) { |log| log.include?('next_event: read_key: "Enter"') }
  settle_repeat_output(session)
  session[:captured].clear
  session[:writer].write("\x10" * 220)
  wait_for_repeat_log(session) { |log| repeat_boundary_count(log) >= 21 }
  settle_repeat_output(session)
  raise "navigation forced a terminal clear" if session[:captured].match?(/\e\[[23]J/)
end

def exercise_repeat_boundary(session)
  before = repeat_render_count(repeat_log(session))
  session[:captured].clear
  session[:writer].write("\x10" * 50)
  log = wait_for_repeat_log(session) { |text| repeat_boundary_count(text) >= 71 }
  settle_repeat_output(session)
  raise "boundary movement redrew a frame" unless repeat_render_count(log) == before
  raise "boundary movement wrote terminal bytes" unless session[:captured].empty?
end

def repeat_render_count(log) = log.scan("handle_command: render").length

def quit_repeat_session(session, pid)
  session[:writer].write("\x18\x03")
  Timeout.timeout(10) do
    loop do
      drain_repeat_output(session)
      result = Process.waitpid2(pid, Process::WNOHANG)
      return result.last.exitstatus if result

      sleep 0.01
    end
  end
end

repository = File.expand_path("..", __dir__)
Dir.mktmpdir("roded-curses-repeat.") do |directory|
  path = File.join(directory, "long.txt")
  original = Array.new(1500) { |row| "row #{row} #{"long_column " * 30}" }.join("\n")
  File.write(path, original)
  log_path = File.join(directory, "roded.log")
  environment = { "TERM" => "xterm-256color", "XDG_CONFIG_HOME" => "#{directory}/config",
                  "XDG_CACHE_HOME" => "#{directory}/cache", "RODED_LOG_PATH" => log_path,
                  "RODED_LOG_LEVEL" => "DEBUG" }
  PTY.spawn(environment, "bundle", "exec", "bin/roded", path, chdir: repository) do |reader, writer, pid|
    reader.winsize = [40, 120]
    session = { reader:, writer:, log_path:, captured: +"" }
    wait_for_repeat_log(session) { |log| log.include?("handle_command: render") }
    settle_repeat_output(session)
    exercise_repeat_scroll(session)
    exercise_repeat_boundary(session)
    raise "curses did not quit cleanly" unless quit_repeat_session(session, pid).zero?
    raise "navigation changed the document" unless File.read(path) == original

    puts "curses repeat smoke passed: 1500 long lines, 220 C-p, no forced screen clear; " \
         "50 further C-p at row 1 produced zero frames and zero terminal bytes"
  ensure
    begin
      Process.kill("TERM", pid)
    rescue StandardError
      nil
    end
  end
end
