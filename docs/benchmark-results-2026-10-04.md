# Long-document benchmark results — 2026-10-04

The benchmark system covers 34 editor operations across core, application,
curses and Qt layers. The measured changes improve cursor movement, scrolling,
editing, buffer switching and window lifecycle. Common plain-text operations on
1500 lines are inexpensive; the 12–30 ms responsiveness target is not reached
for every mode, operation or document size. The remaining costs are recorded
below rather than hidden by a warm syntax cache.

These numbers measure synchronous execution and frontend flush/painting, not
keyboard-to-visible-frame latency. The normal input queues, Qt's 12 ms dispatcher
timer wait and desktop compositor are excluded; curses uses an in-memory screen.
They therefore cannot directly establish parity with published input-latency
figures for other editors. Real terminal and visible Qt correctness checks run
separately.

## Machine, workload and provenance

- AMD Ryzen 7 5825U, Linux x86_64, Ruby 3.4.2 + PRISM, YJIT disabled,
  GC enabled, locked gems including Qt 0.2.0 and curses 1.5.3.
- Deterministic fixture v1; long logical lines, four equally large buffers,
  one initial window. Main runs use the plain profile and seed 264.
- Core/application/curses: 1500 and 10,000 lines, two samples × three operations,
  one warmup operation per sample. Qt complete/large diagnostics: one sample ×
  two operations, no warmup. Focused Qt: two samples × twenty operations, one warmup.
- Offscreen Qt, 960×640 window; curses memory screen, 120×40 cells.
  Runs execute sequentially on the same machine.
- Main measurement implementation SHA-256:
  `2f83a34c57f8f0880fa32e7e8c446084c1e016e36435d74294d88d372c2cd1bd`.
  Consecutive typing additionally records its script hash and workload.

The exploratory `baseline-*` reports were recorded at `4f5595c` with a dirty
checkout. Core/curses measurements preceded their production optimizations;
the Qt baseline already included early core caching work and had the original
Qt renderer. These baselines do not uniquely identify a clean source tree and
should not be treated as reproducible clean-commit performance contracts. The
old Qt viewport bug also limits equivalence of its painted frames.

Candidate core/curses reports were recorded at clean `692caf9`; earlier Qt
reports at clean `1da9eeb`; Ruby native-token reports at clean `6a80352`.
The Qt plain-layout follow-up below was recorded at clean `b13a60c`.
Each original JSON includes its actual source revision, dirty flag, configuration,
fixture hashes and individual measurements. See the [raw archive](../benchmark/results/2026-10-04/README.md)
and [file-hash manifest](../benchmark/results/2026-10-04/manifest.json).

## Curses reset-suite diagnostics

Median execution time in milliseconds. These seven rows illustrate all requested
operation categories; the [complete report](../benchmark/results/2026-10-04/core-curses.json)
contains 204 cases, including core/application layers and the remaining scenarios.

| Operation | 1500 before | 1500 after | 10,000 before | 10,000 after |
| --- | --- | --- | --- | --- |
| Line down | 11.451 | 0.383 | 61.486 | 0.428 |
| Word forward | 216.232 | 0.315 | 1824.169 | 0.454 |
| End of long line | 1188.705 | 1.280 | 1436.442 | 1.345 |
| Horizontal scroll | 69.352 | 1.213 | 99.933 | 1.998 |
| Insert character | 31.611 | 2.507 | 80.988 | 7.952 |
| Next buffer | 30.883 | 1.431 | 73.038 | 1.510 |
| Split vertically | 69.878 | 2.548 | 209.836 | 2.449 |

No median regression above the configured 20% threshold was found across the
204 recorded cases against the exploratory baseline. Six observations per case
are diagnostics, not a stable tail-latency estimate; p95 equals the maximum here.
The [benchmark guide](benchmarks.md) recommends at least 100 observations for a
controlled regression check.

The main changes reuse immutable document snapshots, limit word navigation to
nearby lines, cache window/layout state, detach closed-view edit observers,
coalesce UI publication and avoid repeated character-array geometry on long lines.
Curses updates only changed panes and places the active cursor after rendering.
`C-b` moves the visible caret left on its first press at the right edge; horizontal
scrolling keeps a per-window origin. Boundary cursor keys bypass command execution
and redraw; explicit redraw still refreshes the physical screen.

## Qt execution and painting

The [focused plain-text run](../benchmark/results/2026-10-04/qt-hot.json)
has forty observations per row on 1500 lines. Times are milliseconds.

| Operation | Median ms | p95 ms | Maximum ms |
| --- | --- | --- | --- |
| cursor.char_left | 19.61 | 25.40 | 26.85 |
| cursor.char_right | 19.32 | 23.23 | 26.66 |
| cursor.line_down | 19.47 | 26.75 | 32.59 |
| edit.backspace | 21.54 | 25.47 | 27.15 |
| edit.insert_char | 22.37 | 26.19 | 27.31 |

The current-line fix has no median regression above 20% in these five rows
against the same focused run before the fix. Qt now retains native documents,
updates changed text blocks, indexes UTF-16 row positions and reuses split panes.
The background is an explicit native paragraph format: both the old and new
cursor rows update. Formatting the anchor paragraph stays inside the structural
text edit block, avoiding a second full layout pass.

The complete 1500-line run contains 34 cases and no median regression above 20%
against the exploratory Qt baseline. Selected larger-document diagnostics below
have only two observations per row; they expose remaining expensive operations,
not reliable percentiles. See [complete Qt](../benchmark/results/2026-10-04/qt-full.json)
and [large Qt](../benchmark/results/2026-10-04/qt-large.json).

| Operation | 1500 median ms | 10,000 median ms |
| --- | --- | --- |
| cursor.line_down | 16.16 | 30.66 |
| scroll.horizontal | 16.36 | 29.01 |
| edit.insert_char | 18.18 | 38.61 |
| edit.newline | 23.97 | 74.19 |
| edit.delete_block | 30.70 | 80.05 |
| buffer.next | 76.24 | 443.99 |
| cursor.document_end | 81.50 | 440.47 |
| window.split_vertical | 111.91 | 397.65 |
| window.delete | 32.59 | 84.76 |

## Qt plain-layout follow-up

Qt now uses `QPlainTextEdit` with native inline and paragraph formatting. Its
layout avoids shaping all preceding rows when jumping through a long document.
Split panes copy a native document fragment into independently editable plain
layouts. Structural edits retain and update the UTF-16 position index, avoiding
native cursor traversal through thousands of blocks. Cursor geometry uses cached
snapshot lines instead of splitting the entire document on each render.

The matched [1500-line complete run](../benchmark/results/2026-10-04/qt-plain-layout-full.json)
and [10,000-line selection](../benchmark/results/2026-10-04/qt-plain-layout-large.json)
have no median regression above 20% against the earlier clean Qt reports.
These remain two-observation diagnostics. Selected 10,000-line medians:

| Operation | Earlier ms | Plain layout ms |
| --- | --- | --- |
| cursor.document_end | 440.47 | 31.70 |
| buffer.next | 443.99 | 35.09 |
| edit.newline | 74.19 | 32.29 |
| edit.delete_block | 80.05 | 46.62 |
| window.split_vertical | 397.65 | 105.12 |
| window.delete | 84.76 | 27.39 |

The [focused 1500-line run](../benchmark/results/2026-10-04/qt-plain-layout-hot.json)
uses the same forty-observation configuration as the earlier focused run; all
five medians improve by 22–27%. The separate
[10,000-line focused run](../benchmark/results/2026-10-04/qt-plain-layout-hot-large.json)
has one hundred observations per case. Times are milliseconds:

| Operation | 1500 median | 1500 p95 | 10,000 median | 10,000 p95 |
| --- | --- | --- | --- | --- |
| cursor.char_left | 14.46 | 16.40 | 20.35 | 24.57 |
| cursor.char_right | 14.19 | 16.67 | 20.24 | 27.55 |
| cursor.line_down | 14.85 | 17.89 | 20.79 | 26.84 |
| edit.backspace | 16.14 | 19.48 | 31.74 | 37.16 |
| edit.insert_char | 17.41 | 23.32 | 32.14 | 39.44 |

[Consecutive Qt typing on 1500 lines](../benchmark/results/2026-10-04/qt-plain-layout-typing.json)
has median 16.30 ms, p95 17.85 ms and maximum 20.79 ms over forty operations,
compared with the earlier matched median 23.97 ms. The hundred-observation input
results on 10,000 lines exceed the target even though the short diagnostic input
median is 28.15 ms. These reports still exclude keyboard queues, dispatcher wait
and compositor timing; they do not establish keyboard-to-frame latency.

## Consecutive typing without edited-text cache reuse

Each sample starts once and inserts different successive characters into the
middle row. These measurements include uncached syntax work. Plain/Markdown and
Qt have forty observations per row. The matched Ruby before/after diagnostics
have ten observations on 1500 lines and three on 10,000 lines; their p95 is the
maximum. Times are milliseconds.

| Layer / mode | 1500 median ms | 1500 p95 ms | 10,000 median ms | 10,000 p95 ms |
| --- | --- | --- | --- | --- |
| curses / plain | 2.93 | 3.47 | 8.00 | 11.64 |
| curses / Markdown mode | 4.28 | 4.76 | 19.36 | 23.43 |
| curses / Ruby after | 71.72 | 101.01 | 474.67 | 555.11 |
| Qt / plain, earlier rich layout | 23.97 | 29.06 | — | — |

Ruby's matched medians changed from 270.69 to 71.72 ms on 1500 lines and from
2139.37 to 474.67 ms on 10,000 lines. A separate forty-operation Ruby run gives
median 71.38 ms, p95 96.85 ms, maximum 101.24 ms. All JSON reports are in the archive.

Ruby uses direct native Prism tokens, walks byte line offsets once and reuses
unchanged frozen span rows after comparing the new lexical output. Reuse is
conditional on equal spans, so edits that change multiline string context still
update following rows. Heredocs use Ripper to preserve dedented positions and
ignored whitespace. Parser recovery on malformed Ruby can differ from Ripper;
for example a recovered label after an invalid block prefix remains colored.
Tests cover ordinary lexical equivalence and that recovery behavior separately.

Markdown here means the Markdown mode applied to the long plain fixture, not a
Markdown-heavy document. The plain reset-suite input result alone must not be
used to predict Ruby or other uncached highlighting costs.

## Remaining bottlenecks

- Ruby still lexes the whole document after an uncached edit. Native tokens reduce
  cost, but this remains above 12–30 ms; heredoc documents retain the slower lexer.
  Incremental lexical checkpoints or revision-checked background highlighting
  are further work, not features claimed by these measurements.
- Qt plain layout reduces long-document navigation and buffer-switch costs, but
  first split creation, large block edits and uncached 10,000-line input remain
  expensive. Further document construction and retention changes need separate
  memory/correctness measurements.
- Large block edits still compute whole-document position changes in the core.
  Their allocation cost grows with document length.
- These runs do not measure sustained real keyboard-to-frame throughput,
  compositor timing, native Qt allocations or terminal-emulator I/O. Boundary
  no-ops are checked separately rather than substituted for real motion timings.

## Validation and reproduction

`bundle exec rake` passed after the plain-layout change: 421 examples and RuboCop
across 203 Ruby files.
Visible Qt checks run under private Xvfb with retained widgets and event pumping;
they verify editor/caret geometry, one paragraph background at the cursor row,
modelines, scrolling, buffers, splits and multiline edits. Both plain and Ruby
fixtures passed. Private PTY checks verify input/quit, large buffer/window use,
rapid movement without terminal clears, and zero rendering/output for repeated
`C-p` at the document boundary.

```sh
bundle exec rake
script/curses_live_smoke.rb
script/curses_repeat_live_smoke.rb
script/curses_scale_live_smoke.rb
script/benchmark_qt_live_smoke.sh
RODED_BENCHMARK_PROFILE=ruby script/benchmark_qt_live_smoke.sh
```

See [the benchmark guide](benchmarks.md) for CLI commands, strict baseline
compatibility, filtering, layers and report interpretation. Create fresh clean
before/after runs with matching environment and at least 100 observations before
using these exploratory improvements as a performance budget for CI.
