#!/usr/bin/env ruby

require "fileutils"
require "io/console"
require "io/wait"
require "pty"
require "tmpdir"

MINIBUFFER_RENDER = "publish_ui_update: minibuffer_render"
MINIBUFFER_CLEAR = "publish_ui_update: minibuffer_clear"

def drain_output(reader, captured)
  loop { captured << reader.read_nonblock(65_536) }
rescue IO::WaitReadable, EOFError, Errno::EIO
  nil
end

def send_input(session, bytes, delay: 0.35)
  session.fetch(:writer).write(bytes)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + delay
  while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    drain_output(session.fetch(:reader), session.fetch(:captured))
    sleep 0.03
  end
end

def log_count(session, text)
  return 0 unless File.file?(session.fetch(:log_path))

  File.read(session.fetch(:log_path)).scan(text).length
end

def wait_for_log_count(session, text, target)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 15
  loop do
    drain_output(session.fetch(:reader), session.fetch(:captured))
    return if log_count(session, text) >= target
    if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      raise "timed out waiting for #{text.inspect} count #{target}"
    end

    sleep 0.05
  end
end

def type_minibuffer(session, value)
  target = log_count(session, MINIBUFFER_RENDER) + value.length
  send_input(session, value, delay: 0.1)
  wait_for_log_count(session, MINIBUFFER_RENDER, target)
end

def submit_minibuffer(session, value, clear_target)
  type_minibuffer(session, value)
  send_input(session, "\r", delay: 0.3)
  wait_for_log_count(session, MINIBUFFER_CLEAR, clear_target)
end

def wait_for_file(path, expected, session)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
  loop do
    drain_output(session.fetch(:reader), session.fetch(:captured))
    actual = File.binread(path) if File.file?(path)
    return if actual == expected
    if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      raise "unexpected contents in #{path}: #{actual.inspect}"
    end

    sleep 0.05
  end
end

def save_current(session, path, expected)
  send_input(session, "\x18\x13", delay: 0.5)
  wait_for_file(path, expected, session)
end

def query_replace_all(session, query, replacement)
  renders = log_count(session, MINIBUFFER_RENDER)
  clears = log_count(session, MINIBUFFER_CLEAR)
  send_input(session, "\e<", delay: 0.3)
  send_input(session, "\e%", delay: 0.4)
  wait_for_log_count(session, MINIBUFFER_RENDER, renders + 1)
  submit_minibuffer(session, query, clears + 1)
  submit_minibuffer(session, replacement, clears + 2)
  submit_minibuffer(session, "!", clears + 3)
end

def save_as(session, path, expected)
  renders = log_count(session, MINIBUFFER_RENDER)
  clears = log_count(session, MINIBUFFER_CLEAR)
  send_input(session, "\x18\x17", delay: 0.4)
  wait_for_log_count(session, MINIBUFFER_RENDER, renders + 1)
  submit_minibuffer(session, File.basename(path), clears + 1)
  wait_for_file(path, expected, session)
end

def edit_command_line_files(session, paths)
  send_input(session, "X", delay: 0.2)
  save_current(session, paths.fetch(:text), "Xcat dog cat\n")
  send_input(session, "\x18\e[D", delay: 0.5)
  send_input(session, "Y", delay: 0.2)
  save_current(session, paths.fetch(:ruby), "Yputs \"cat\"\n")
end

def edit_shared_ruby_view(session, path)
  send_input(session, "\x183", delay: 0.5)
  send_input(session, "\x05\x18o", delay: 0.4)
  send_input(session, "Z", delay: 0.2)
  save_current(session, path, "YZputs \"cat\"\n")
  send_input(session, "\x18o", delay: 0.4)
  send_input(session, "W", delay: 0.2)
  save_current(session, path, "YZputs \"cat\"W\n")
end

def query_replace_and_save_as(session, path, copy_path, after)
  query_replace_all(session, "cat", "fox")
  save_current(session, path, after)
  save_as(session, copy_path, after)
end

def reopen_text_copy(session)
  renders = log_count(session, MINIBUFFER_RENDER)
  clears = log_count(session, MINIBUFFER_CLEAR)
  send_input(session, "\x18k", delay: 0.5)
  send_input(session, "\x18\x06", delay: 0.5)
  wait_for_log_count(session, MINIBUFFER_RENDER, renders + 1)
  submit_minibuffer(session, "notes-copy.txt", clears + 1)
end

def exercise_line_search(session)
  renders = log_count(session, MINIBUFFER_RENDER)
  clears = log_count(session, MINIBUFFER_CLEAR)
  send_input(session, "\x13", delay: 0.3)
  wait_for_log_count(session, MINIBUFFER_RENDER, renders + 1)
  submit_minibuffer(session, "dog", clears + 1)
end

def exercise_region_history(session, path)
  send_input(session, "\e<", delay: 0.3)
  send_input(session, "\0", delay: 0.2)
  send_input(session, "\x06\x17", delay: 0.4)
  save_current(session, path, "fox dog fox\n")
  send_input(session, "\x19", delay: 0.3)
  save_current(session, path, "Xfox dog fox\n")
  send_input(session, "\x1f", delay: 0.3)
  save_current(session, path, "fox dog fox\n")
  send_input(session, "\x03rd", delay: 0.4)
  save_current(session, path, "Xfox dog fox\n")
end

def exercise_reopened_copy(session, path)
  reopen_text_copy(session)
  exercise_line_search(session)
  exercise_region_history(session, path)
end

def run_acceptance(session, paths)
  edit_command_line_files(session, paths)
  edit_shared_ruby_view(session, paths.fetch(:ruby))
  query_replace_and_save_as(
    session, paths.fetch(:ruby), paths.fetch(:ruby_copy), "YZputs \"fox\"W\n"
  )
  send_input(session, "\x18\e[C", delay: 0.5)
  query_replace_and_save_as(session, paths.fetch(:text), paths.fetch(:text_copy), "Xfox dog fox\n")
  exercise_reopened_copy(session, paths.fetch(:text_copy))
  send_input(session, "\x18\x03", delay: 0.5)
end

def abort_if_still_running(pid, deadline, smoke_dir)
  return if Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline

  Process.kill("TERM", pid)
  Process.wait(pid)
  abort "curses acceptance smoke did not quit; artifacts=#{smoke_dir}"
end

def wait_for_exit(session, pid, smoke_dir)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 15
  loop do
    drain_output(session.fetch(:reader), session.fetch(:captured))
    result = Process.waitpid2(pid, Process::WNOHANG)
    return result.last.exitstatus if result

    abort_if_still_running(pid, deadline, smoke_dir)
    sleep 0.05
  end
end

repository = File.expand_path("..", __dir__)
smoke_dir = Dir.mktmpdir("roded-curses-two-file.", "/tmp")
config_dir = File.join(smoke_dir, "config")
cache_dir = File.join(smoke_dir, "cache")
FileUtils.mkdir_p([config_dir, cache_dir])
paths = {
  ruby: File.join(smoke_dir, "editor.rb"),
  text: File.join(smoke_dir, "notes.txt"),
  ruby_copy: File.join(smoke_dir, "editor-copy.rb"),
  text_copy: File.join(smoke_dir, "notes-copy.txt"),
  log: File.join(smoke_dir, "roded.log")
}
File.write(paths.fetch(:ruby), "puts \"cat\"\n")
File.write(paths.fetch(:text), "cat dog cat\n")
environment = {
  "BUNDLE_GEMFILE" => File.join(repository, "Gemfile"),
  "RBENV_DIR" => repository,
  "TERM" => "xterm-256color",
  "XDG_CONFIG_HOME" => config_dir,
  "XDG_CACHE_HOME" => cache_dir,
  "RODED_LOG_PATH" => paths.fetch(:log),
  "RODED_LOG_LEVEL" => "DEBUG"
}
captured = +""
exit_status = nil

PTY.spawn(
  environment, "bundle", "exec", File.join(repository, "bin/roded"), "editor.rb", "notes.txt", chdir: smoke_dir
) do |reader, writer, pid|
  reader.winsize = [24, 80]
  session = { reader:, writer:, captured:, log_path: paths.fetch(:log) }
  sleep 1
  run_acceptance(session, paths)
  exit_status = wait_for_exit(session, pid, smoke_dir)
end

expected_files = {
  ruby: "YZputs \"fox\"W\n",
  text: "Xfox dog fox\n",
  ruby_copy: "YZputs \"fox\"W\n",
  text_copy: "Xfox dog fox\n"
}
expected_files.each do |name, expected|
  actual = File.binread(paths.fetch(name))
  abort "#{name} contents mismatch: #{actual.inspect}; artifacts=#{smoke_dir}" unless actual == expected
end
unless exit_status&.zero? && File.read(paths.fetch(:log)).include?("publish_ui_update: quit")
  abort "curses acceptance smoke failed: exit=#{exit_status.inspect}; artifacts=#{smoke_dir}"
end
File.binwrite(File.join(smoke_dir, "curses-output.ansi"), captured)
puts "curses two-file acceptance passed; artifacts=#{smoke_dir}"
