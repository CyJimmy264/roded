require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

task default: %i[spec rubocop]

namespace :release do
  desc "Run tests and lint, build the gem and verify its extracted runtime"
  task check: %i[spec rubocop build] do
    require_relative "lib/roded/version"
    ruby "script/release_smoke.rb", "pkg/roded-#{Roded::VERSION}.gem"
  end
end

desc "Measure long-document editor performance (options: BENCH_ARGS='--lines 1500 --layers core')"
task :benchmark do
  require "shellwords"
  ruby "benchmark/run.rb", *Shellwords.split(ENV.fetch("BENCH_ARGS", ""))
end
