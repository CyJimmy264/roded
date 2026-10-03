# Qt binding workarounds

## QTextCursor move-operation enum names

- **Location:** `lib/roded/frontends/qt/editor_window.rb`
- **Observed binding:** qt 0.1.9 on Ruby 3.4.2, Qt Widgets 6.11.2.
- **Gap:** `QPlainTextEdit#move_cursor` is exposed, but generated constants do not
  include `QTextCursor::MoveOperation` names.
- **Reproducer:** `require "qt"; p Qt::QTextCursor.constants.grep(/Start|Right|Down/)`
  returns no move-operation values. The installed Qt header
  `/usr/include/qt6/QtGui/qtextcursor.h` defines `Start`, `Down`, and `Right`
  in that order at enum values 1, 12, and 19.
- **Workaround:** keep those three public Qt enum values in the presentation
  adapter and apply them after setting the read-only widget text. This moves only
  the Qt presentation cursor; document text, point, and edits remain in Roded core.
- **Limits:** this early Qt slice resets text from core snapshots and does not yet
  implement selection or mouse-to-core point mapping. The workaround covers
  initial caret placement only.
- **Verification:** a real Qt 6.11.2 desktop widget accepted text, cursor
  placement, layout, event subscriptions, and QTimer dispatch. An XTest/xdotool
  smoke sent `Super+j` and `Alt+Super+comma`; Qt delivered these as `s-j` and
  `M-s-,`, and the mapped commands ran. This verifies Qt's synthetic X11 input
  path, not physical keyboard hardware. Mouse, selection, clipboard, and
  physical Super-key checks remain open.
- **Removal:** add generated `QTextCursor::MoveOperation` enum constants to qt,
  then replace the integer values with their named bindings and remove the TODO.

## QClipboard text access

- **Location:** `lib/roded/frontends/qt/clipboard_bridge.rb`
- **Observed binding:** qt 0.1.9 on Ruby 3.4.2, Qt Widgets 6.11.2.
- **Gap:** `QApplication.clipboard` returns a `Qt::QObject` wrapper without
  `QClipboard#text` or `QClipboard#setText`; those calls are unavailable from Ruby.
- **Reproducer:** `QApplication.clipboard.class` is `Qt::QObject`, and the
  returned object's public methods do not include `text` or `set_text`.
- **Workaround:** a transport-only `QTextEdit` invokes Qt's native `paste` and
  `copy` slots. It is always cleared and never stores editor state. Clipboard
  paste is translated to one core `:paste` event; `C-S-c`/`C-S-x` invoke core
  region-copy/kill commands, whose clipboard writes return through the GUI
  dispatcher. `C-S-v` keeps Emacs `C-v` available for page-down.
- **Limits:** this supports mark-based region copy/cut and text paste. Native
  mouse selection/context-menu routing remains part of the larger Qt parity work.
- **Verification:** the offscreen Qt 6.11.2 widget round-tripped multiline UTF-8
  text including a non-BMP emoji; the Qt key callback produced a core paste
  event with the same text, source id, and active window id. Core specs confirm
  copy leaves the document intact and cut keeps undoable edits/KillRing state.
- **Removal:** expose `QClipboard#text` and `QClipboard#setText` in qt and replace
  the transport widget with those direct clipboard calls.

## Vetoing a native close event

- **Location:** `lib/roded/frontends/qt/input_router.rb` and
  `lib/roded/frontends/qt/close_guard.rb`.
- **Observed binding:** qt 0.1.9 on Ruby 3.4.2, Qt Widgets 6.11.2.
- **Gap:** event callbacks expose a consume/ignore result, but no result that
  vetoes `QWidget::close` while preventing the default `QWidget::closeEvent`.
- **Reproducer:** with a real `QWidget`, `on(:close) { :consume }` accepts the
  event and hides the widget. Returning `:ignore` falls through to the default
  close event, which also hides it.
- **Workaround:** route close to core and retain the view. If core returns a
  prompt, status message, or cancel update, the GUI dispatcher shows the same
  widget again. Accepted quit clears the pending close and leaves it hidden.
- **Limits:** cancellation is verified offscreen; desktop manager behavior and
  save/discard prompts still need a live UI smoke.
- **Verification:** `spec/qt_frontend_close_spec.rb` calls native `QWidget.close`,
  observes `Event(:close_request)`, then checks that the prompt and cancel path
  restore a visible Qt window.
- **Removal:** expose a Qt event-filter result that ignores and consumes the
  close event before the default handler, then replace `QtCloseGuard` with it.
