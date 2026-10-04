# Changelog

## [Unreleased]

## [0.2.0] - 2026-10-05

### Added

- Qt desktop frontend alongside curses, with split panes, mouse selection,
  wheel scrolling, system clipboard integration and a visible block caret.
- Multiple file buffers and independent window cursors, horizontal/vertical
  splits, buffer switching and window resizing.
- Safe file open/save/save-as, external-change detection, reload and
  save/discard/cancel flows for modified buffers and quit.
- Per-buffer grouped undo/redo, multiline paste, marked regions, kill ring,
  yank replacement and read-only protection.
- Command, buffer, path, project-file, line and kill-ring pickers; search,
  goto-line, query replace, picker history and keybinding help.
- Ruby, JSON, YAML and Markdown highlighting, configurable key sequences,
  text/indentation commands and a programmable in-process Ruby REPL.
- Reproducible benchmarks for 34 operations, consecutive typing and real Qt
  key-to-frame latency, including 1500/10,000 rows, 2500/10,000-character
  lines, Unicode, multiple buffers and large windows.

### Changed

- Frontend-independent core owns editor state and commands; frontends consume
  immutable snapshots with explicit input source and window identities.
- Reuse document/syntax snapshots and exact edit ranges. Curses redraws changed
  panes/rows; Qt retains native documents and updates changed blocks or caret
  formats. Boundary navigation performs no unnecessary redraw.
- Large Ruby edit highlighting runs in a child process with revision checks;
  Qt dispatch wakes on queued updates and uses Fusion unless a style is specified.
- Release packages contain runtime files and maintained documentation; benchmark
  archives, agent skills, tests and development scripts remain in the checkout.
- Require Ruby 3.4.2+, qt 0.2.x and explicitly declare the Prism lexer dependency.

### Fixed

- Empty files, final newlines, supported LF/CRLF data, atomic saves, symlink
  handling and modified-state restoration after undo.
- Unicode/codepoint/UTF-16/tab coordinate mapping, edits in repeated text and
  position transforms for multiple views of one document.
- Curses long-line cursor latency, backward movement at the right edge,
  held-key flicker, terminal key decoding and bracketed paste.
- Qt current-line highlighting, caret clipping, blank-row geometry,
  minibuffer/modeline updates, shortcut routing and cancelled native close.
- Qt event-loop GVL starvation, accumulating scroll-timer callbacks and
  horizontal scrolling that left neighboring rows at stale positions.
- Lifecycle shutdown on quit, EOF, signals and errors; isolated Qt tests and
  live PTY/Xvfb acceptance checks.
- Query-replace confirmation and replace-all through real input after UI-update
  batching; match detection no longer depends on the return value of rendering.
- Curses syntax/selection/search attributes leaking onto neighboring text after
  scrolling; styling uses character columns instead of the screen row.

Performance figures and measurement limits are recorded in
[the optimization report](docs/optimization-final-report-2026-10-05.md).

## [0.1.0] - 2025-03-16

- Initial release
