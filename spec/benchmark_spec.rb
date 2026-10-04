require "spec_helper"
require "stringio"
require "open3"
require_relative "../benchmark/roded/cli"

# rubocop:disable Metrics/BlockLength
RSpec.describe Roded::Benchmarking::Fixture do
  it "produces deterministic 1500-line documents with long lines and distinct profiles" do
    fixtures = described_class::PROFILES.map { |profile| described_class.new(line_count: 1500, profile:) }
    fixtures.each do |fixture|
      expect(fixture.text.split("\n").length).to eq(1500)
      expect(fixture.text.split("\n").map(&:length).min).to be > 250
      copy = described_class.new(line_count: 1500, profile: fixture.profile)
      expect(copy.metadata).to eq(fixture.metadata)
    end
    expect(fixtures.map { |fixture| fixture.metadata[:sha256] }.uniq.length).to eq(3)
  end
end

RSpec.describe Roded::Benchmarking::Scenarios do
  let(:fixture) { Roded::Benchmarking::Fixture.new(line_count: 1500, profile: "plain") }

  described_class.all.each do |scenario|
    it "executes #{scenario.name} with multiple windows and resets its state" do
      work = Roded::Benchmarking::Workspace.new(layer: "core", fixture:, buffer_count: 4, window_count: 2)
      2.times do
        work.reset
        scenario.prepare.call(work)
        work.render
        scenario.action.call(work)
        expect(scenario.verify.call(work)).to be(true)
      end
      work.reset
      expect(work.application.windows).to eq(work.base_windows)
      expect(work.buffer.to_s).to eq(fixture.text)
      expect(work.buffer.instance_variable_get(:@edit_observers)).to match_array(work.base_windows)
    ensure
      work&.close
    end
  end
end

RSpec.describe Roded::Benchmarking::Runner do
  it "stores measured repetitions separately from warmup and verifies each operation" do
    config = Roded::Benchmarking::Options::DEFAULTS.merge(lines: [1500], layers: ["application"],
                                                          samples: 2, iterations: 3, warmup: 1)
    scenario = Roded::Benchmarking::Scenarios.all.find { |item| item.name == "edit.insert_char" }
    verification = spy("verification", call: true)
    scenario = scenario.with(verify: verification.method(:call))
    report = described_class.new(config, output: StringIO.new).run([scenario])
    row = report[:results].first

    expect(verification).to have_received(:call).exactly(8).times
    expect(row[:samples].map(&:length)).to eq([3, 3])
    expect(row[:metrics][:operations]).to eq(6)
    expect(row[:metrics][:median_ms]).to be_positive
    expect(row[:metrics][:allocated_objects_per_operation]).to be_positive
    expect(report[:fixtures].first[:lines]).to eq(1500)
  end

  it "fails instead of reporting timings for a broken scenario" do
    config = Roded::Benchmarking::Options::DEFAULTS.merge(lines: [1500], layers: ["core"],
                                                          samples: 1, iterations: 1, warmup: 0)
    scenario = Roded::Benchmarking::Scenario.new("broken", ->(_work) {}, ->(_work) {}, ->(_work) { false })
    expect { described_class.new(config, output: StringIO.new).run([scenario]) }
      .to raise_error(RuntimeError, /verification failed: broken/)
  end
end

RSpec.describe Roded::Benchmarking::Statistics do
  it "computes latency percentiles and throughput from individual operations" do
    samples = [1, 2, 3, 4].map do |milliseconds|
      { wall_ns: milliseconds * 1_000_000, allocated_objects: 10, gc_runs: 1, gc_ns: 100_000 }
    end
    metrics = described_class.summarize([samples.take(2), samples.drop(2)])
    expect(metrics).to include(operations: 4, median_ms: 2.5, p95_ms: 4.0, max_ms: 4.0,
                               operations_per_second: 400.0, allocated_objects_per_operation: 10.0,
                               gc_runs: 4, gc_ms: 0.4)
  end
end

RSpec.describe Roded::Benchmarking::Comparison do
  let(:baseline) do
    {
      "schema_version" => 1,
      "config" => described_class::CONFIG_FIELDS.to_h { |key| [key, 1] },
      "environment" => described_class::ENVIRONMENT_FIELDS.to_h { |key| [key, "same"] },
      "fixtures" => [{ "lines" => 1500, "sha256" => "fixture" }],
      "results" => [{ "layer" => "core", "lines" => 1500, "scenario" => "cursor.line_down",
                      "metrics" => { "median_ms" => 2.0, "p95_ms" => 4.0,
                                     "allocated_objects_per_operation" => 100 } }]
    }
  end
  let(:candidate) { Marshal.load(Marshal.dump(baseline)) }

  it "reports slower medians and flags only changes beyond the configured threshold" do
    candidate["results"][0]["metrics"]["median_ms"] = 2.5
    row = described_class.new(baseline, candidate, threshold: 20).results.first
    expect(row).to include(change_percent: 25.0, p95_change_percent: 0.0,
                           allocations_change_percent: 0.0, regression: true)
    expect(described_class.new(baseline, candidate, threshold: 30).results.first[:regression]).to be(false)
  end

  it "reports improvements without calling them regressions" do
    candidate["results"][0]["metrics"]["median_ms"] = 1.0
    expect(described_class.new(baseline, candidate, threshold: 20).results.first)
      .to include(change_percent: -50.0, regression: false)
  end

  %w[iterations buffers windows].each do |field|
    it "rejects changed workload #{field}" do
      candidate["config"][field] = 2
      expect { described_class.new(baseline, candidate, threshold: 20) }
        .to raise_error(ArgumentError, /config.#{field}/)
    end
  end

  it "rejects measurements from a changed harness or machine" do
    candidate["environment"]["harness_sha256"] = "different"
    expect { described_class.new(baseline, candidate, threshold: 20) }
      .to raise_error(ArgumentError, /harness_sha256/)
  end

  it "rejects changed fixture contents and missing baseline scenarios" do
    candidate["fixtures"][0]["sha256"] = "different"
    expect { described_class.new(baseline, candidate, threshold: 20) }
      .to raise_error(ArgumentError, /incompatible fixture/)
    candidate["fixtures"] = baseline["fixtures"]
    candidate["results"][0]["scenario"] = "missing"
    expect { described_class.new(baseline, candidate, threshold: 20).results }
      .to raise_error(ArgumentError, /no result/)
  end

  it "permits a selected subset of baseline results" do
    candidate
    baseline["results"] << baseline["results"].first.merge("scenario" => "extra")
    expect(described_class.new(baseline, candidate, threshold: 20).results.length).to eq(1)
  end
end

RSpec.describe Roded::Benchmarking::Isolation do
  it "uses private config and offscreen Qt then restores settings and logging even on failure" do
    original = ENV.to_h.slice("XDG_CONFIG_HOME", "XDG_CACHE_HOME", "QT_QPA_PLATFORM")
    previous_logger = Roded::Logging.logger
    expect do
      described_class.run(xvfb: false) do
        expect(ENV.fetch("QT_QPA_PLATFORM")).to eq("offscreen")
        expect(ENV.fetch("XDG_CONFIG_HOME")).to include("roded-benchmark-")
        expect(File.directory?(ENV.fetch("XDG_CONFIG_HOME"))).to be(true)
        expect(Roded::Logging.logger).not_to equal(previous_logger)
        raise "test failure"
      end
    end.to raise_error("test failure")
    expect(ENV.to_h.slice(*original.keys)).to eq(original)
    expect(Roded::Logging.logger).to equal(previous_logger)
  end
end

RSpec.describe Roded::Benchmarking::Options do
  ["--lines 1499", "--samples 0", "--iterations -1", "--buffers 1", "--windows 0", "--warmup -1",
   "--layers unknown", "--profile unknown", "--fail-on-regression", "--max-regression -1"].each do |arguments|
    it "rejects invalid configuration #{arguments}" do
      expect { described_class.new.parse(arguments.split) }.to raise_error(ArgumentError)
    end
  end
end

RSpec.describe "benchmark command line" do
  it "writes raw JSON, isolates exported desktop settings, and returns failure for a regression" do
    Dir.mktmpdir("roded-bench-spec-") do |directory|
      path = File.join(directory, "baseline.json")
      arguments = %w[bundle exec ruby benchmark/run.rb --lines 1500 --layers core --samples 1
                     --iterations 2 --warmup 0 --scenarios ^cursor.line_down$]
      environment = { "QT_QPA_PLATFORM" => "xcb", "XDG_CONFIG_HOME" => "#{directory}/desktop" }
      _stdout, stderr, status = Open3.capture3(environment, *arguments, "--output", path)
      expect(status.success?).to be(true), stderr
      report = JSON.parse(File.read(path))
      expect(report["environment"]["qt_platform"]).to eq("offscreen")
      expect(report["results"][0]["samples"][0].length).to eq(2)
      report["results"][0]["metrics"]["median_ms"] = 0.000001
      File.write(path, JSON.generate(report))
      candidate = File.join(directory, "candidate.json")
      stdout, stderr, status = Open3.capture3(environment, *arguments, "--output", candidate,
                                              "--baseline", path, "--fail-on-regression")
      expect(status.exitstatus).to eq(1), stderr
      expect(stdout).to include("REGRESSION")
      expect(JSON.parse(File.read(candidate))["comparison"][0]["regression"]).to be(true)
      expect(File.exist?(environment["XDG_CONFIG_HOME"])).to be(false)
    end
  end
end
# rubocop:enable Metrics/BlockLength
