# Long-document benchmark results — 2026-10-04

The final Russian report consolidates the whole optimization effort, original and
current operation tables, real-key measurements, and the long-line/timer follow-up:
[optimization-final-report-2026-10-05.md](optimization-final-report-2026-10-05.md).
The sections below retain their original stage-specific numbers and provenance.

The benchmark system covers 34 editor operations across core, application,
curses and Qt layers. The measured changes improve cursor movement, scrolling,
editing, buffer switching and window lifecycle. Common plain-text operations on
1500 lines are inexpensive; the 12–30 ms responsiveness target is not reached
for every mode, operation or document size. The remaining costs are recorded
below rather than hidden by a warm syntax cache.

These numbers measure synchronous execution and frontend flush/painting, not
keyboard-to-visible-frame latency. The normal input queues, Qt's dispatcher
scheduling and desktop compositor are excluded; curses uses an in-memory screen.
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
Edit-range reports use clean `b4596c2` before and `c085675` after;
the unformatted Qt-copy follow-up uses clean `e348e88`.
Qt damaged-region reports use clean `bfdf4cf` before and `b58976e` after;
the broader follow-up uses clean `e4296e6`, and exact edit positions use `08df59a`.
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

## Edit-range and pane-copy follow-ups

`c085675` finds edit ranges without allocating an object for every character.
It skips equal prefix/suffix lines, compares UTF-8 bytes with character-aligned
boundaries, and maps only the range endpoints back to logical positions.
Inputs outside valid UTF-8/ASCII retain character-based comparison. Tests compare against a
character-based oracle on 600 generated Unicode cases and verify precise
replacement/undo/redo ranges, including edits inside a 1500-line document.

The matched [before](../benchmark/results/2026-10-04/edit-range-before.json)
and [after](../benchmark/results/2026-10-04/edit-range-after.json) reports contain
24 cases, forty observations each: insert, backspace, newline and delete-block
across core/application/curses on 1500 and 10,000 lines. There is no median
regression above 20%. Deleting 100 rows gives:

| Layer / lines | Before median ms | After median ms | After p95 ms |
| --- | --- | --- | --- |
| core / 1500 | 10.018 | 0.436 | 0.516 |
| core / 10,000 | 7.073 | 1.307 | 1.610 |
| application / 10,000 | 15.255 | 7.038 | 10.499 |
| curses / 1500 | 12.473 | 2.480 | 2.675 |
| curses / 10,000 | 18.674 | 7.925 | 10.700 |

Core delete-block allocations decrease from about 33,595 to 239 objects per
operation (99.3%); character insertion decreases from 737 to 78. The
[Qt diagnostic](../benchmark/results/2026-10-04/edit-range-qt-large.json)
shows delete-block median 40.77 ms, compared with 46.62 ms before this change.
The [100-observation Qt input run](../benchmark/results/2026-10-04/edit-range-qt-hot.json)
still gives median 31.55 ms for insertion and 31.86 ms for backspace; p95 values
are 37.19 and 36.18 ms. Fewer allocated objects do not remove that remaining cost.

`e348e88` copies unformatted Qt panes as native plain text and restores the
caret/current-row formatting. This path requires uniform monospace fonts and no
syntax spans, selection or search highlight; other documents retain native
fragment copying. Editor font and wrap settings are established before copying.
Tests and visible frames verify Unicode, expanded tabs, empty/EOL caret cells,
independent documents, syntax colors and selections.

The [complete 1500-line report](../benchmark/results/2026-10-04/qt-plain-copy-full.json)
and [15-case 10,000-line report](../benchmark/results/2026-10-04/qt-plain-copy-large.json)
have no median regression above 20% against `b13a60c`. These are two-observation
diagnostics. On 10,000 lines the first recorded vertical split decreases from
145.35 to 120.15 ms, while the second split reusing a pooled pane changes from
64.89 to 63.99 ms. The two-operation median changes from 105.12 to 92.07 ms;
it must not be presented as the cost of first pane creation or a reliable tail
estimate. First creation remains well above the target.

## Qt damaged-region painting and exact edit positions

`b58976e` removes unconditional repaint requests for the editor viewport and
the entire pane after normal movement, scrolling or modeline updates. Qt paints
the regions changed by its document, scrollbar and label operations. Explicit
refresh retains one full repaint even when subsequent layout updates coalesce.

The matched [before](../benchmark/results/2026-10-04/qt-damage-before.json) and
[after](../benchmark/results/2026-10-04/qt-damage-after.json) runs each have forty
observations per case. Times are milliseconds:

| Operation / lines | Before median | After median | After p95 | After maximum |
| --- | --- | --- | --- | --- |
| Character left / 1500 | 14.68 | 8.82 | 10.26 | 11.62 |
| Line down / 1500 | 15.20 | 9.40 | 11.83 | 13.24 |
| Insert character / 1500 | 16.33 | 10.71 | 11.92 | 12.50 |
| Character left / 10,000 | 17.85 | 12.37 | 14.39 | 15.90 |
| Line down / 10,000 | 18.42 | 12.58 | 13.25 | 16.54 |
| Insert character / 10,000 | 30.06 | 23.82 | 26.09 | 37.46 |

All ten matched cases improve in median without a regression above 20%.
The [complete 1500-line](../benchmark/results/2026-10-04/qt-damage-full.json)
and [15-case 10,000-line](../benchmark/results/2026-10-04/qt-damage-large.json)
diagnostics also have no median regression above 20% against the plain-copy
reports. Their two observations do not establish tail behavior. The first
recorded 10,000-line vertical split takes 110.89 ms; pooled-pane reuse takes
55.53 ms. First creation remains expensive.

The longer [100-observation run](../benchmark/results/2026-10-04/qt-damage-hot.json)
has higher costs than the forty-observation run: 10,000-line insertion median
27.45 ms, p95 33.72 ms, maximum 49.60 ms. It has no configuration-matched
pre-repaint baseline, so its differences from the shorter run are not a measured
regression. The target is still exceeded in some tails.

Long consecutive typing exposed a correctness error in the existing range
derivation: inserting a letter identical to the next letter could report the
insertion at a later position, leaving the caret behind. `08df59a` supplies the
known insertion/deletion/split/join/region boundaries directly. Arbitrary whole
document replacements retain derived ranges. Repeated Unicode, blank rows,
multiple views, marks, grouped typing and undo/redo have regression coverage.
The [matched 100-observation reset run](../benchmark/results/2026-10-04/exact-edit-qt-hot.json)
has no median regression above 20% against `e4296e6`.

The clean consecutive plain Qt input reports after this correction give:

| Lines / observations | Median ms | p95 ms | Maximum ms |
| --- | --- | --- | --- |
| [1500 / 40](../benchmark/results/2026-10-04/exact-edit-typing-1500.json) | 10.73 | 12.13 | 27.99 |
| [10,000 / 100](../benchmark/results/2026-10-04/exact-edit-typing-10000.json) | 24.12 | 27.97 | 28.90 |

These consecutive workloads and the reset suite differ and must be interpreted
separately. The attempted pre-correction 100-insert stream failed correctness
verification; it supplies no valid performance baseline. The earlier successful
[1500-line stream](../benchmark/results/2026-10-04/qt-damage-typing-1500.json)
is retained with its original provenance.

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

## Deferred Ruby coloring and the real Qt event loop

`59e903f` publishes text/caret updates immediately after edits to Ruby documents
of at least 1500 rows. A child interpreter computes coloring; requests coalesce
per buffer, and only matching revision/job results are applied on the core thread.
Changed rows temporarily lose coloring while unchanged rows retain the previous
decoration. Complete lexical context is restored when the result arrives.
The child sends only changed rows in bounded frames and is reaped on shutdown.

Each clean report below has two samples of fifty consecutive edits. Times are
milliseconds. The final-color wait is measured separately after each sample and
includes result delivery and frontend painting:

| Layer / lines | Foreground median | Foreground p95 | Foreground maximum | Final-color waits |
| --- | --- | --- | --- | --- |
| [curses / 1500](../benchmark/results/2026-10-04/background-ruby-curses-1500.json) | 10.07 | 12.17 | 16.57 | 258 / 234 |
| [Qt / 1500](../benchmark/results/2026-10-04/background-ruby-qt-1500.json) | 16.40 | 19.00 | 29.10 | 246 / 247 |
| [curses / 10,000](../benchmark/results/2026-10-04/background-ruby-curses-10000.json) | 23.52 | 27.51 | 44.30 | 1338 / 1361 |
| [Qt / 10,000](../benchmark/results/2026-10-04/background-ruby-qt-10000.json) | 35.08 | 37.54 | 41.02 | 1363 / 1339 |

The scope changes from synchronous fully colored frames to initial text/caret
frames. The new harness SHA-256 is
`8b9080dfd3ad1299f16f8ce82fe8116f806edfbc0d1d1b250c79b8ba26f04122`.
Strict comparison with earlier reports is rejected. These figures are not a
same-work speedup of the lexer. Initial coloring remains synchronous, and Qt
foreground input on 10,000 rows still exceeds the target before keyboard/timer
costs are added.

`a1e5a0d` corrects a different defect in qt 0.2.0: its FFI binding held Ruby's
GVL throughout QApplication.exec. Manual event pumping returned from native code
and did not expose this. The adapter reattaches only exec with `blocking: true`,
preserving QApplication's lifecycle and keeping widget calls on the GUI thread.
The clean [original probe](../benchmark/results/2026-10-04/qt-exec-original.json)
records one ticker wakeup over 403.36 ms, with a maximum gap of 403.38 ms.
The [released probe](../benchmark/results/2026-10-04/qt-exec-released.json)
records 358 wakeups over 403.57 ms, maximum gap 24.05 ms including adapter
installation/disposal. A native timer calls Ruby only to finish; production has
additional GUI callbacks. These probes demonstrate Ruby thread progress, not
keyboard-to-pixel latency, and retain their raw gaps and source metadata.

See the [KWrite source review and alternatives](qt-rendering-alternatives.md) for
its separate QWidget/QPainter/QTextLayout renderer, damaged-area painting and
layout reuse. The current frontend is retained following the user's confirmation
of improved responsiveness; renderer replacement is deferred. Separating
caret/decorations from HTML edits remains an option if measurements justify it.

## Real Qt keys and server-side frames

`307a0e8` adds a separate-process XTest/pixel benchmark. It runs the actual
QApplication/core loops and the production 12 ms dispatcher. Each key waits for
its changed block caret to appear and the preceding caret to disappear in the
Xvfb frame. Core point/line oracles also run. Snapshot matching distinguishes the
input's render from unrelated background highlighting. `2c7c82d` records the
horizontal origin and rejects changes that invalidate this caret-only oracle.

Nine clean reports from `2c7c82d` contain 2840 observed keystrokes. Paired workloads
use 200 keys per group (100 per direction/action); consecutive typing uses 100
keys. Both use four warmup keys. The original-binding comparison is exploratory,
with 20 keys per group (10 per cursor direction). These are serialized input
latencies, not held-key throughput or physical display latency. Values include
instrumentation, IPC and a 1 ms polling interval, and are upper bounds on Xvfb
server-side frame latency. They cannot be equated with published measurements
from other editors.

| Fixture / lines | Cursor medians | Insert / backspace medians | Consecutive typing median / p95 / max |
| --- | --- | --- | --- |
| [plain / 1500](../benchmark/results/2026-10-04/qt-key-plain-1500.json) | 16.35–18.29 | 18.41 / 19.52 | [17.25 / 22.46 / 53.20](../benchmark/results/2026-10-04/qt-key-typing-plain-1500.json) |
| [plain / 10,000](../benchmark/results/2026-10-04/qt-key-plain-10000.json) | 19.27–21.16 | 30.23 / 31.15 | [27.49 / 38.16 / 111.63](../benchmark/results/2026-10-04/qt-key-typing-plain-10000.json) |
| [Ruby / 1500](../benchmark/results/2026-10-04/qt-key-ruby-1500.json) | 19.99–20.66 | 22.00 / 22.61 | [19.88 / 30.82 / 45.53](../benchmark/results/2026-10-04/qt-key-typing-ruby-1500.json) |
| [Ruby / 10,000](../benchmark/results/2026-10-04/qt-key-ruby-10000.json) | 24.33–24.58 | 41.89 / 42.52 | [39.81 / 50.88 / 175.99](../benchmark/results/2026-10-04/qt-key-typing-ruby-10000.json) |

All times are milliseconds. Cursor medians cover `C-f`, `C-b`, `C-n`, `C-p`.
The [original binding](../benchmark/results/2026-10-04/qt-key-original-1500.json)
has cursor medians 131.41 / 132.51 ms and typing median 134.71 ms on plain 1500
rows. This confirms that the event-loop correction affects actual keys/frames,
not just an independent ticker. The 12–30 ms target is still not met across
operations, sizes and upper percentiles.

The raw phase timestamps distinguish native delivery, the core queue, core work
and snapshot creation, dispatcher waiting, widget application and frame detection.
For Ruby 10,000-row typing, core/snapshot work, Qt application and frame detection
remain substantial. The final syntax colors are not required by this frame
oracle; background lexer CPU can compete with foreground work.

A longer plain typing diagnostic fails at the right edge before scrolling starts:
after key 116, core point is row 750 / column 120 (zero-based), native caret x=942,
horizontal origin=0. The custom blue block extends outside the viewport. See the
[captured frame](../benchmark/results/2026-10-04/qt-block-caret-right-edge.png).
The probe correctly refuses to report a painted caret there. This exposed a
frontend clipping bug, separate from the latency measurements above, which remain
within the viewport. The old visibility logic allowed the cursor's character
offset up to the full viewport width without reserving document margin/block width.

The fix reserves the expanded caret cell and document margins when deciding
whether to restore a horizontal origin. Revealing point also scrolls far enough
to show the whole colored cell, rather than only Qt's two-pixel native cursor.
Width measurement supplies Qt's required UTF-16 length, including tabs/wide text;
the document margin is read through QObject's property API because qt 0.2 does
not expose a `document_margin` accessor. Unit geometry regressions and live
right-edge pixel checks pass. The long real-key probe now reaches a changed
horizontal origin and rejects that unsupported measurement instead of timing out
on an invisible caret.

The main benchmark also drains viewport feedback before resetting a case, and
allows horizontal-scroll events while settling deferred syntax. These actions
remain outside foreground timing. Its harness digest changes, so strict
comparison against earlier reset-suite reports is intentionally rejected.

## Event-driven Qt dispatcher

The frontend now requests one GUI wakeup when an update arrives, rather than
running a Ruby callback every 12 ms. A GUI-owned, zero-delay single-shot timer
applies the queue; Qt's reentrant `QTimer.singleShot` queues its `start()` slot
from the producer thread. Pending snapshots share a wakeup. Updates posted during
application request a subsequent wakeup; stopping preserves queued actions for
manual drain or restart. Tests cover these cases and real GUI-thread delivery.

The real-key harness also starts its readiness timer after initial document
construction and window show. Previously, constructing 10,000 Ruby rows could
exhaust the 200 ms delay before the native loop began. The initial frame check
then rejected stale caret coordinates: it expected `(35, 16)`, while the visible
caret was at `(35, 160)`. No input was sent in that failed run. Moving the start
fixes this benchmark startup race; no pixel check was relaxed.

Four fresh reports use the same corrected latency harness
`dc5722e8188239490658574178c0de8b893b610b681b1f6368062e0307fd43aa`.
Each has 600 observations, 100 per operation, from clean sources. The event-driven
source is `36d5d36`; the periodic reference `6e54b2f` is `084b7b7` plus only the
readiness correction. Its exact commit is retained in
`benchmark/results/2026-10-04/qt-periodic-reference.bundle`, with `084b7b7` as a
prerequisite. Runs used separate private Xvfb sessions sequentially.

Median real-key-to-caret-frame latency, milliseconds:

| Fixture | Operation | Periodic 12 ms | Event-driven |
| --- | --- | ---: | ---: |
| Plain, 1500 rows | Character/line motion, range | 21.90–22.95 | 22.68–23.60 |
| Plain, 1500 rows | Insert | 24.18 | 24.53 |
| Plain, 1500 rows | Backspace | 23.98 | 25.21 |
| Ruby, 10,000 rows | Character/line motion, range | 25.40–26.84 | 27.77–28.60 |
| Ruby, 10,000 rows | Insert | 46.06 | 46.77 |
| Ruby, 10,000 rows | Backspace | 48.36 | 47.94 |

This is not an overall input-latency improvement. Motion medians are somewhat
higher in the event-driven run, with the difference mostly in the XTest-to-Qt
input-receipt phase. Widget application remains about 5–6 ms on the large Ruby
fixture. A single pair of runs cannot establish the cause of that delivery change.
The change is retained for removing idle polling and reducing dispatcher-wait
tails, rather than claiming a faster complete frame.

For motion, dispatcher-wait p95 falls from 2.86–3.77 to 0.17–0.20 ms on plain
1500 rows, and from 6.89–7.98 to 0.18–0.20 ms on Ruby 10,000 rows. The median
dispatch wait rises slightly, from about 0.09–0.11 to 0.14–0.15 ms. Ruby edit
dispatch remains small: p95 changes from 0.25–0.40 to 0.53–0.59 ms; its main cost
is elsewhere. Whole-frame p95 still reaches about 67 ms and maxima about 183 ms.

The six one-second idle windows per implementation show 1.42–1.79% of one CPU
core for periodic polling versus 0.0085–0.0127% for event-driven delivery. These
are editor-process CPU samples, excluding Xvfb/controller/lexer processes. They
demonstrate the elimination of idle Ruby wakeups, not battery-life measurements.

Two additional clean `084b7b7` reports retain the interval-only experiment with
the preceding harness: 12 versus 4 ms polling, 600 observations each. Both show
about 23–24 ms medians on 1500 plain rows; idle CPU increases from 0.62–0.68% to
1.30–1.44% of one core. Their harness differs from the four corrected-readiness
reports, so compare those two interval reports to each other only.

All six reports and the reference bundle have SHA-256 entries in the manifest.
`bundle exec rake` passes with 458 examples and RuboCop across 235 files. Native
input/close checks, a 10,000-line/31-buffer check, and sixteen Ruby visible-frame
checks pass, including caret/current-row/modeline, scrolling, splits and edits.

## Remaining bottlenecks after the latest changes

- Ruby still lexes the whole document after an uncached edit. Large-document input
  no longer waits for it, but coloring can lag more than a second on 10,000 rows.
  Initial coloring remains synchronous; heredocs retain the slower lexer.
  Incremental lexical checkpoints remain further work.
- Qt plain layout reduces long-document navigation and buffer-switch costs, but
  first split creation, large block edits and uncached 10,000-line input remain
  expensive. Further document construction and retention changes need separate
  memory/correctness measurements.
- Shared snapshots and serialized text are still rebuilt after document edits.
  Application work for plain input grows from about 1 ms on 1500 lines to about
  6.5 ms on 10,000 lines even after edit-range allocations are removed.
- These runs do not measure sustained real keyboard-to-frame throughput,
  compositor timing, native Qt allocations or terminal-emulator I/O. Boundary
  no-ops are checked separately rather than substituted for real motion timings.
- The real-key probe now covers eleven cursor/edit cases, including word and page
  motion with the live page size and checked viewport origins. Scrolling, buffer
  switches and window lifecycle still need equivalent real-key
  frame measurements in addition to the main suite's execution/visible checks.
  Right-edge block-caret clipping is fixed in the existing frontend.

## Validation and reproduction

`bundle exec rake` passed after the right-edge correction: 454 examples and RuboCop
across 233 Ruby files. Trace regressions cover unrelated/stale background renders,
latest matching snapshots and reuse of the preceding key's target. Real XTest
and pixel checks passed on both fixture sizes and profiles.
Visible Qt checks run under private Xvfb with retained widgets and event pumping;
they verify editor/caret geometry, one paragraph background at the cursor row,
modelines, scrolling, buffers, splits and multiline edits. Both plain and Ruby
fixtures passed. Optional screenshot assertions check the actual row background,
cleared neighboring rows and block-caret pixels for fifteen plain operations and
sixteen Ruby operations; the checks run sequentially under private Xvfb.
The Ruby profile additionally checks a quote edit that changes following lexical
context, compares final spans with the complete lexer and checks native colors.
Tests cover stale results, mode changes, heredoc/Unicode/history, worker failure
and real core-loop cleanup. Xvfb keyboard checks pass for typing, save, undo,
close confirmation and a 10,000-line file with 31 buffers.
Private PTY checks verify input/quit, large buffer/window use,
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
