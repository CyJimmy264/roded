# Qt binding workaround status

## Resolved by qt 0.2.0

The Qt 0.1.9 workarounds below were removed after upgrading the runtime
dependency to `qt ~> 0.2.0`. The released gem exposes the APIs described in
`/home/mveynberg/Code/Ruby/qt/tmp/roded_solutions.md`; Roded now uses them
directly:

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
