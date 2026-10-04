require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

task default: %i[spec rubocop]

desc "Measure long-document editor performance (options: BENCH_ARGS='--lines 1500 --layers core')"
task :benchmark do
  require "shellwords"
  ruby "benchmark/run.rb", *Shellwords.split(ENV.fetch("BENCH_ARGS", ""))
end
