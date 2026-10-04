---
name: roded-frontend-performance
description: Diagnose and verify Roded core, curses and Qt latency or painting regressions using reproducible long-text benchmarks and isolated visible-frame checks.
---

# Roded frontend performance

Use this skill for slow editor commands, held-key behavior, long-line scrolling,
or cursor/row painting regressions. Work from the repository root.
Read [benchmark commands and scopes](../../../docs/benchmarks.md) for the relevant
harness and [Qt implementation](../../../docs/qt-frontend.md) when the Qt path is involved.
The [optimization report](../../../docs/optimization-final-report-2026-10-05.md)
retains historical measurements and their limits; do not treat them as a new run.

## Reproduce the actual workload

Distinguish number of rows from line length. Match cursor column, syntax mode,
buffer/window count, viewport dimensions and actual key bindings. A 10,000-row
fixture with 300-character lines does not cover a 2500-character line at column
1200. Prepare visited buffers before timing if latency depends on switching.
Keep boundary/no-op movement and repeated input as separate cases.

Choose the measurement that answers the complaint:

- `benchmark/run.rb`: core/application/curses/Qt command plus adapter completion.
  Preparation/reset/verification are outside timing; this is not keyboard-to-pixel latency.
- Consecutive typing harness: state accumulates within a sample; exposes growing work
  hidden by resetting after every operation.
- `benchmark/qt_key_latency.rb`: native XTest input through the normal Qt loop to
  independent X11 caret pixels. It excludes physical display/compositor latency.
- `benchmark/qt_event_loop_probe.rb`: Ruby thread progress during QApplication.exec;
  manual process_events can hide GVL starvation.
- `benchmark/qt_horizontal_scroll_smoke.rb`: unchanged neighboring rows must move
  and match a fresh viewport paint. The latency harness rejects changing horizontal
  origins because its previous-caret pixel oracle becomes ambiguous.

Run formal measurements sequentially with no competing CPU work. Record fixture
hash, source revision/dirty state, harness hash, style, geometry, sample count and
latency scope. Compare compatible configurations; report p95/outliers and final
syntax-color settling separately from foreground text/caret latency.

## Native pitfalls demonstrated in Roded

- Qt callbacks/widgets belong to the GUI thread. Queue domain snapshots through
  QtUiDispatcher; retain QApplication/widgets during probes.
- QApplication.exec's FFI call must release Ruby's GVL. A responsive process_events
  loop does not prove the real application loop lets core/input threads progress.
- Connect a reused QTimer's callback once, then restart/coalesce it. Reconnecting
  during render accumulates handlers and latency; check beginning/end of a long run.
- Suspend only Roded's horizontal-scroll feedback. Blocking scrollbar valueChanged
  also suppresses Qt's native scrolling and leaves unchanged rows at stale pixels.
- When origin/layout changes, a caret-row-only paint is insufficient. Check adjacent
  rows, current-row background, modeline, full caret width and blank/EOL cells.
- Curses StyledSegment.first_offset is the character offset; Struct.first returns
  its screen-row field. Verify syntax/selection/search on the same text at different
  screen rows and horizontal origins to detect attribute bleed.
- Core uses codepoints, Qt uses UTF-16 offsets, curses uses cells; expand tabs and
  test surrogate pairs/combining characters instead of assuming ASCII coordinates.
- Preserve Qt character/block format value lifetime when using native bindings.
  Fast caret formatting is conditional on unchanged content/tokens and no selection
  or search overlay; retain fallback paths for structural/EOL changes.
- Match style when comparing Alt/Meta input. Roded defaults to Fusion; Breeze
  introduced mnemonic repaint overhead. Honor an explicit style override.
- UI batching may defer publication and return nil. Return domain match/edit results
  explicitly; test query-replace and similar prompts through routed keys/Enter.
  Direct method calls outside a UI batch can hide this failure.
- For edits, test repeated characters/blank lines: a minimal text diff may locate
  an equivalent range instead of the actual edit and move other views incorrectly.

## Verify the result

Specs use forced offscreen Qt/private XDG config. Live Qt runs use a private Xvfb,
curses uses a private PTY; do not read user keymaps or touch the desktop session.
Pump events on the GUI thread for live-widget checks. Verify painted pixels when
the failure is visual; a scrollbar value or changed to_plain_text alone is insufficient.
Use a pre-fix/negative control when useful to show the regression check detects the failure.

Run the relevant behavior checks and live smoke, then `bundle exec rake`.
Keep raw historical JSON immutable. Update the maintained report/CHANGELOG with
measured scope and remaining limits; avoid introducing a universal latency promise.
