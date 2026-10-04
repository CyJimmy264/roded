# Qt binding workaround status

## Resolved by qt 0.2.0

The Qt 0.1.9 workarounds below were removed after upgrading the runtime
dependency to `qt ~> 0.2.0`. Roded uses the installed binding directly for:

- Scoped enum constants replace numeric cursor movement and line-wrap values.
- `QApplication.clipboard.text` and `set_text` replace the transport `QTextEdit`.
- The `:reject` close-event result keeps a native window open while core handles
  a close request; `QtCloseGuard` was deleted.
- `QTextEdit#text_cursor` and `#set_text_cursor` place the caret at an explicit
  UTF-16 document offset, including positions inside grapheme clusters.
- `QSplitter#sizes` and `#set_sizes` apply core pane ratios directly.

Regression coverage lives in `spec/qt_editor_window_spec.rb`,
`spec/qt_clipboard_bridge_spec.rb`, and `spec/qt_frontend_close_spec.rb`.
The installed 0.2.0 API was probed in a private offscreen Qt process before
updating the integration. Run the Qt specs with the repository's normal
`spec_helper` environment isolation.

## Disabling the native text context menu

- **Location:** `lib/roded/frontends/qt/editor_pane.rb`.
- **Behavior:** `QTextEdit` defaults to `DefaultContextMenu`; the keyboard Menu
  event opened native Copy/Select All actions instead of reaching Roded's
  project and buffer picker bindings.
- **Implementation:** set `Qt::NoContextMenu`. The Qt key translator continues
  routing Menu and Alt+Menu to core.
- **Verification:** the offscreen widget reports `NoContextMenu`, and
  `spec/qt_shortcut_routing_spec.rb` checks both Menu key routes.
- **Status:** this is a supported Qt API choice, not a binding workaround.

## Native event loop and GUI wakeup

- **Location:** `lib/roded/frontends/qt/event_loop.rb`.
- **Gap:** qt 0.2.0 attaches QApplication.exec without FFI `blocking: true`,
  starving Ruby core/input/IPC threads while the native loop owns the GVL.
- **Adaptation:** reattach only `qt_ruby_qapplication_exec` with `blocking: true`,
  retaining the gem's exec wrapper and GUI-thread callbacks. No installed gem is patched.
- **Verification:** `spec/qt_event_loop_spec.rb` and
  `benchmark/qt_event_loop_probe.rb --qt-xvfb`, plus native-loop live checks.
- **Removal:** use the gem's normal entry point once its binding releases the GVL;
  retain the native-loop progress regression.

`QtUiDispatcher` uses the exposed native `qtimer_single_shot` receiver/slot form
to queue a zero-delay wake on its GUI-owned timer. A core thread cannot call
ordinary QTimer.start directly. `spec/qt_ui_dispatcher_spec.rb` covers coalescing
and wake scheduling. The scroll-restoration timer connects once per pane.

## Native format values

`current_line_format.rb` and `caret_format_operations.rb` use the installed
native character/block-format APIs. Owned format values are deleted in ensure;
editor/template widgets remain referenced. Document-renderer/current-line specs
and pixel-based live checks cover these paths. When extending this code, inspect
the installed generated bindings and value lifetimes before changing FFI calls.
