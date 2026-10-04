# Repository Guidelines

## Structure and contracts

- `lib/roded` contains the editor core; `lib/roded/frontends` contains curses and Qt adapters.
  See [architecture](docs/architecture.md) before changing ownership or message flow.
- Buffer owns document text and undo history. Window owns point, mark, viewport and remembered buffer positions.
  Preserve exact edit locations when transforming other views, including edits in repeated text.
- The core is the single writer of editor state. Route keys, M-x and Ruby API through the shared command contract.
  Preserve input source/window identities and independent pending key sequences.
- Frontends consume immutable snapshots; reuse unchanged document data rather than copying it per cursor movement.
  Rendering must not mutate domain state. Viewport feedback is an explicit input event.
- Return domain results explicitly. Deferred UI publication can return nil; it must not determine match/edit success.
  Test interactive workflows through routed keys, including minibuffer submissions, not only direct method calls.
- Modelines and prompts belong to frontends. Application diagnostics go through Logging, never directly to stdout.
- QApplication, Qt widgets and callbacks belong to the GUI thread. Cross-thread updates use QtUiDispatcher.
- `bin/roded` selects one frontend per launch. Specs, live checks and benchmarks live in `spec`, `script`, `benchmark`.

## Commands and style

- `bin/setup` installs dependencies; `bundle exec bin/roded [file ...]` starts curses;
  `bundle exec bin/roded --frontend qt [file ...]` starts Qt.
- `bundle exec rake` runs RSpec and RuboCop. Use targeted checks while iterating, then the full gate.
- Ruby 3.4.2+, double-quoted strings, no new frozen-string-literal headers.
  One top-level class/module per library file, snake_case paths/methods, PascalCase types.
- `bundle exec rake build` builds a gem in `pkg`; `bundle exec rake release:check` verifies tests, lint and the package.
  Release procedure: [docs/releasing.md](docs/releasing.md). Keep version, lockfile and CHANGELOG consistent.

## Regression checks

- RSpec examples describe observable behavior. Cover routing, mutations, undo and affected views for editor changes.
- `spec/spec_helper.rb` must force offscreen Qt and private per-process XDG config, even if desktop settings are exported.
  Standalone Qt probes also need private XDG paths. Live UI checks use private Xvfb or PTY, not the desktop DISPLAY.
- Visual Qt changes need a live-widget check: retain QApplication/widgets, change them on the GUI thread and pump events.
  Verify visible caret/current-line/modeline/scrolling; changed document text alone does not prove a painted frame.
- For native-loop scheduling use `benchmark/qt_event_loop_probe.rb`; manual process_events can hide GVL starvation.
- For horizontal paint changes use `benchmark/qt_horizontal_scroll_smoke.rb` in private Xvfb.
  Neighboring rows must move with the active row. Suppress our feedback, not native scrollbar signals.
- For terminal keyboard mapping use `script/curses_xvfb_keyboard_smoke.sh` (private Alacritty/Xvfb).
  Preserve Kitty CSI-u reporting, legacy decoding and a tested fallback binding.
- Curses styling uses character columns, not screen rows. Check syntax/selection/search at different scroll origins;
  StyledSegment.first_offset is the character offset, while Struct.first returns its screen-row field.
- `script/curses_live_smoke.rb` checks real PTY input/quit. The two-file acceptance scripts exercise both frontends
  through editing, split/shared views, search/replace, save-as, reopen and undo/redo.

## Performance and reusable skill

For editor latency, painting or long-text regressions, read the repository skill
[roded-frontend-performance](.agents/skills/roded-frontend-performance/SKILL.md).
It contains the measurement choices and native rendering pitfalls learned during optimization.
Detailed commands: [benchmarks](docs/benchmarks.md); retained evidence:
[optimization report](docs/optimization-final-report-2026-10-05.md) and `benchmark/results`.

Run formal benchmarks sequentially on an otherwise idle machine. Preserve fixture/harness/environment metadata;
report actual observation counts, latency scope and remaining limits. Keep historical JSON unchanged.
Use long lines/deep columns, multiple buffers and realistic window dimensions when those trigger the complaint.

## Documentation and commits

Maintain current contracts and reproducible commands, not GOAL/PLAN files or per-step work journals.
Use Git history for completed investigations. Keep useful benchmark provenance and technical limitations.
Commit finished changes with short imperative messages. PRs explain behavior and relevant verification;
flag binding/file-I/O changes and update README/CHANGELOG when user behavior changes.
