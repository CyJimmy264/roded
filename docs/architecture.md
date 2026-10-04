# Editor architecture

Roded has a frontend-independent Ruby core and two adapters: curses and Qt.
One launch selects one frontend; the input contracts support independently identified sources.

## State and commands

`EditorSession` owns documents, active window, focus and the split tree.
`Buffer` owns immutable document snapshots, file metadata, modified state and undo/redo.
`Window` owns point, mark, scroll origins and remembered positions when switching buffers.
Multiple windows share a buffer's text while preserving independent positions.
Edits carry their actual replacement range so other views transform correctly,
including repeated characters, blank lines, Unicode and undo.

`InputEvent` carries input and source/window geometry. `CommandRouter` resolves
per-source key sequences; `CommandRegistry` provides the common contract for
keys, M-x and the Ruby editor API. `EditorCommand` represents the requested
operation and `UIUpdate` carries presentation updates. The application core
serializes domain mutations and publishes immutable snapshots after commands.
A frontend never edits a live Buffer as a side effect of painting.
Domain predicates/results are independent of UI publication return values:
render batching may defer an update and return nil. Interactive regressions must
exercise routed input and minibuffer submission as well as direct domain calls.

`FileService` owns file I/O, atomic replacement and external-change detection.
Core workflows coordinate path prompts, reload/overwrite/cancel and closing
modified buffers. Saving preserves supported line endings, final-newline state,
permissions and symlink targets. Errors preserve edits and modified state.

## Frontends and background work

Curses decodes terminal input, presents snapshots with cell-aware geometry and
updates damaged panes/rows. Geometry changes and horizontal scroll invalidate
partial-row redraws. Boundaries that cannot move point do not trigger redraw.

Qt runs QApplication/widgets on the main thread and the core on its worker thread.
`QtUiDispatcher` coalesces queued updates and schedules a GUI wake only when work
arrives. Each pane retains a read-only QPlainTextEdit document; native editing
and native undo are disabled. The core owns editing, selection and history.
See [Qt frontend](qt-frontend.md) and [binding adaptations](qt-workarounds.md).

Syntax services return token spans without changing text or history. Ruby uses
Prism, with Ripper handling heredoc positions. After edits in Ruby documents of
at least 1500 rows, a child interpreter performs full-context highlighting.
Requests coalesce per buffer and results are accepted only for the current
revision. Foreground text/caret updates and final coloring have separate latency.
Initial coloring remains synchronous.

The in-process Ruby REPL has a persistent binding and routes supported editor
API mutations through the core. It is trusted Ruby execution, not a sandbox.
See README for supported operations and interruption limits.

## Verification

[Keybindings](keybindings.md) document user commands. Specs check headless core
contracts and isolated Qt widgets; PTY/Xvfb acceptance checks verify live flows.
[Benchmarks](benchmarks.md) distinguish command/adapter timings from native
key-to-frame latency. [Release checks](releasing.md) verify the assembled gem.
