# Long-document performance benchmarks

Run from the checkout with Ruby 3.4.2 and the locked Bundler dependencies. No
additional gems are needed. Benchmarks are separate from `bundle exec rake` so
normal correctness checks have no machine-dependent latency thresholds.

```sh
bundle exec rake benchmark
# Equivalent, with explicit report location:
bundle exec ruby benchmark/run.rb --output tmp/benchmarks/baseline.json
# A smaller first run:
bundle exec rake benchmark BENCH_ARGS='--lines 1500 --samples 2 --iterations 3'
bundle exec ruby benchmark/run.rb --list
bundle exec ruby benchmark/run.rb --help
```

Defaults: 1500, 5000 and 10,000 logical lines, four equally large buffers, one
window, five independent samples with ten measured operations each, and two
warmup operations per sample. All fixture lines exceed 250 characters so the
same documents exercise both long files and horizontal scrolling. Fixtures have
fixed contents and a recorded version/SHA-256; there is no file download or disk
I/O in the timed operation. Use `--profile ruby` for syntax highlighting or
`--profile unicode` for Cyrillic, wide characters, emoji, combining marks and tabs.

The complete suite can take several minutes on the current editor. Qt is
particularly expensive and is selected explicitly. Filter a suspected bottleneck
before increasing repetition counts.

## Measurement layers

| `--layers` value | Timed work |
| --- | --- |
| `core` | The production command path and document/view mutations; `publish_ui_update` is suppressed in a benchmark subclass. |
| `application` | The same path, including immutable snapshots, syntax spans and update delivery to a sink that retains nothing. |
| `curses` | Application plus the production curses renderer on a 120×40 in-memory monochrome screen. Includes clipping, geometry, modelines and incremental redraw; excludes ncurses calls and terminal/emulator I/O. |
| `qt` | Application plus the real Qt frontend, coalescing dispatcher, widgets, layout, repaint and three `QApplication.process_events` passes per operation. Uses a 960×640 window. |

All operations run synchronously. The normal application event queue, OS keyboard
delivery and Qt's 12 ms dispatcher timer wait are outside these measurements.
For Qt, the timer is stopped and the production dispatcher is explicitly drained
on the GUI thread once per operation; updates posted by one operation can still
coalesce. This measures execution/painting cost, not key-to-photon latency or
sustained input throughput. Offscreen paint timings also differ from X11.

Qt defaults to `offscreen` even if the caller exported `xcb` or a desktop display.
To measure visible X11 widgets, use `--qt-xvfb`: the launcher creates its own Xvfb
and selects `xcb`. Both modes use temporary XDG configuration/cache directories
and silent benchmark logging, without reading the user's keymap or Qt settings.

```sh
bundle exec ruby benchmark/run.rb --lines 1500 --layers curses \
  --scenarios 'cursor.line_|scroll.' --output tmp/benchmarks/curses.json
bundle exec ruby benchmark/run.rb --lines 1500 --layers qt --qt-xvfb \
  --samples 2 --iterations 3 --scenarios 'cursor.line_down|scroll.page_down|edit.insert_char' \
  --output tmp/benchmarks/qt-x11.json
script/benchmark_qt_live_smoke.sh
```

The live Qt smoke check retains the application/widgets, changes them on the GUI
thread and pumps events. It checks visible editor geometry, caret styling and
position, old/new paragraph backgrounds, multiline edits, modeline updates,
vertical/horizontal scrollbars, buffer switching and split creation/removal.
Use `RODED_BENCHMARK_PROFILE=ruby script/benchmark_qt_live_smoke.sh` to exercise
syntax-colored native documents. The existing `script/curses_live_smoke.rb` and
`script/curses_scale_live_smoke.rb` cover real terminal behavior separately.
`script/curses_repeat_live_smoke.rb` verifies held-key scrolling and boundary
no-ops in a private PTY: no terminal clear during movement and no rendering or
terminal output for further `C-p` presses at the beginning of the document.

## Scenarios and state

The catalog in `benchmark/roded/scenarios.rb` contains 34 scenarios:

- Cursor: character, line, word and page in both directions; line/document boundaries.
- Viewport: line/page vertical scrolling in both directions; horizontal origin change plus render.
- Editing: insert, backspace, forward delete, newline, paste a 100-line block,
  delete a 100-line region, undo and redo.
- Buffers: next/previous buffer in the same window.
- Windows: split horizontally/vertically, delete, activate another window, delete other windows.
- Diagnostics: full render and a `C-n` key routed through the actual keymap.

Roded currently has no paragraph/block cursor command. Word and page movement
measure its available larger navigation steps; block edits measure multiline
operations. Additional commands can be added to the scenario catalog when implemented.

Before every invocation, the harness restores the original text/history, active
buffer, window tree, point, mark and viewport. The initial point is in the middle
of the document. Cursor and scrolling operations therefore always move instead
of eventually measuring a boundary no-op. A page operation is explicitly 38
logical lines across all layers, independent of split geometry. Setup, initial
render and behavioral verification are outside timing and allocation counters.

Resetting each invocation can reuse syntax cached for an identical edited
document. Also measure consecutive typing to expose uncached highlighting:

```sh
bundle exec ruby benchmark/typing_stream.rb --mode plain --lines 1500 \
  --layer curses --samples 5 --iterations 20 --output tmp/benchmarks/typing-plain.json
bundle exec ruby benchmark/typing_stream.rb --mode ruby --lines 10000 \
  --layer qt --samples 5 --iterations 20 --output tmp/benchmarks/typing-ruby.json
```

The stream prepares/renders once per sample, then inserts successive characters
without resetting or warming the edited-text cache. It supports plain, Ruby,
JSON, YAML and Markdown modes. Ruby uses the Ruby fixture; the other modes use
the long plain fixture with that highlighting mode enabled. Markdown timings
therefore do not represent a Markdown-heavy real document. The standalone stream
report records its own script hash and workload/configuration; it is not a main
suite report and cannot be passed to `benchmark/run.rb --baseline`. Compare
streams with matching mode, fixture, machine, script/harness hashes and counts.

Each sample owns a new application. Temporary split views are detached from
buffer edit observers during reset, including views already removed by a delete
operation; benchmark repetitions do not accumulate stale observers. This reset
is benchmark infrastructure, not a change to production window lifecycle behavior.
Buffers/windows can be varied to expose fan-out costs:

```sh
bundle exec ruby benchmark/run.rb --lines 1500,10000 --buffers 30 --windows 4 \
  --scenarios 'edit.insert_char|buffer.|window.' --output tmp/benchmarks/multi-view.json
```

## Reports and regression checks

The table shows median/p95/maximum latency in milliseconds and allocated Ruby
objects per operation. JSON additionally stores mean, reciprocal mean execution
rate, GC runs/time, every individual operation measurement grouped by sample,
fixture metadata, Ruby/YJIT/gem versions, CPU/host, benchmark implementation hash,
Git revision and whether the checkout was dirty. Allocations do not include
native Qt memory. GC remains enabled; a full collection runs once after warmup,
before each sample. Measured GC counts/time include only collections inside
timed operations. Reset/setup allocations can influence subsequent GC scheduling.

Median and p95 use all individual measured operations, not averages of batches.
The median averages the middle pair for even counts; p95 uses nearest rank.
Small runs are smoke/diagnostic measurements: with fewer than twenty operations,
p95 is the maximum. For a focused optimization use at least 100 observations:

```sh
bundle exec ruby benchmark/run.rb --lines 1500,10000 --layers core,application \
  --samples 5 --iterations 20 --scenarios 'cursor.line_down|edit.insert_char' \
  --output tmp/benchmarks/before.json

# Make the production optimization, then repeat the same workload/options:
bundle exec ruby benchmark/run.rb --lines 1500,10000 --layers core,application \
  --samples 5 --iterations 20 --scenarios 'cursor.line_down|edit.insert_char' \
  --baseline tmp/benchmarks/before.json --output tmp/benchmarks/after.json \
  --max-regression 20 --fail-on-regression
```

Positive percentages mean slower/more allocations. A median increase greater
than the threshold is marked `REGRESSION`. p95 and allocation changes are reported
alongside it, but do not independently trigger failure. Exit codes: 0 success,
1 measured regression with `--fail-on-regression`, 2 invalid options or incompatible
reports. Verification/runtime failures also exit nonzero. A measured regression
still writes the candidate JSON report.

Comparison rejects changed fixtures, harness, Ruby/gem versions, machine,
Qt platform, YJIT/GC options and workload/repetition parameters. The production
Git revision may change: that is what an optimization comparison needs. Baseline
results may be a superset of candidate scenarios/line counts, provided the
environment and measurement options match; missing matching rows are errors.
The `--seed` option fixes the shuffle of scenario/layer/size tasks (default 264).
Keep the machine otherwise idle, run comparisons sequentially, and repeat noisy
differences before treating them as a regression. Thresholds are opt-in for CI
on controlled hardware; there is no universal speed limit in normal specs.

To extend the system, add a `Scenario` with preparation, one logical action, and
a verification predicate. Preparation and verification are untimed. Add a
behavioral harness spec, run the relevant frontend smoke check, and regenerate
both reports after changing the harness because its implementation hash changes.

Recorded runs, their limitations and remaining bottlenecks are in
[the 2026-10-04 results](benchmark-results-2026-10-04.md).
