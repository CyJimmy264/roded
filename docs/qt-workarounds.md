# Qt binding workarounds

## QTextCursor move-operation enum names

- **Location:** `lib/roded/frontends/qt/cursor_mapper.rb`
- **Observed binding:** qt 0.1.9 on Ruby 3.4.2, Qt Widgets 6.11.2.
- **Gap:** `QTextEdit#move_cursor` is exposed, but generated constants do not
  include `QTextCursor::MoveOperation` names.
- **Reproducer:** `require "qt"; p Qt::QTextCursor.constants.grep(/Start|Right|Down/)`
  returns no move-operation values. The installed Qt header
  `/usr/include/qt6/QtGui/qtextcursor.h` defines `Start`, `Down`, and `Right`
  in that order at enum values 1, 12, and 19.
- **Workaround:** keep those three public Qt enum values in `QtCursorMapper` and
  apply them after setting the read-only widget text. Core character columns are
  mapped to complete grapheme boundaries before using the Qt `Right` operation.
- **Limits:** QTextCursor remains unavailable for reading the native position;
  mouse-to-core point mapping is still open.
- **Verification:** a real Qt 6.11.2 desktop widget accepted text, cursor
  placement, layout, event subscriptions, and QTimer dispatch. An XTest/xdotool
  smoke sent `Super+j` and `Alt+Super+comma`; Qt delivered these as `s-j` and
  `M-s-,`, and the mapped commands ran. This verifies Qt's synthetic X11 input
  path, not physical keyboard hardware. Mouse, selection, clipboard, and
  physical Super-key checks remain open.
- **Removal:** add generated `QTextCursor::MoveOperation` enum constants and
  QTextEdit cursor accessors to qt, then set a converted UTF-16 position directly.

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

## Setting the QTextEdit cursor position

- **Location:** `lib/roded/frontends/qt/cursor_mapper.rb` and
  `lib/roded/frontends/qt/editor_pane.rb`.
- **Observed binding:** qt 0.1.9 on Ruby 3.4.2, Qt Widgets 6.11.2.
- **Gap:** the generated `QTextEdit` wrapper omits `textCursor()` and
  `setTextCursor()`. The editor supports `moveCursor(MoveOperation, MoveMode)`,
  but the cursor itself cannot be read or placed at a document/UTF-16 offset.
- **Reproducer:** a real offscreen `QTextEdit` responds to `move_cursor` and
  `copy`; its public methods have no `text_cursor`/`set_text_cursor`. Cursor
  movement skips a combined grapheme such as `e` plus a combining accent and a
  ZWJ family emoji as single visual units.
- **Workaround:** add a unique private-use marker to the rendered HTML at the
  exact core character boundary. `QTextEdit#find` locates it, and replacing the
  selected marker with an empty string leaves Qt's native caret at that UTF-16
  offset. The document is briefly made writable for this presentation-only
  operation; native undo is disabled and no core text event is emitted. The
  marker is removed synchronously before Qt paints the widget.
- **Limits:** this provides exact visual caret placement, including between
  codepoints inside combining and ZWJ graphemes. Direct QTextCursor APIs remain
  unavailable, and mouse-to-core point mapping is still open.
- **Verification:** a real Qt Widgets offscreen `QTextEdit` showed the following
  combining mark after placing the caret between a base and its combining mark,
  and showed the remainder of a family emoji after placing the caret after its
  first codepoint. Carets after astral and complete ZWJ graphemes also map to the
  expected next character. `spec/qt_editor_window_spec.rb` covers these cases.
- A previous live smoke used XTest/`xdotool` against the active X11 display.
  That can inject input into the user's desktop despite filesystem sandboxing
  and may have caused visible desktop activity. Do not repeat it outside an
  isolated display such as Xvfb; it did not prove physical keyboard delivery.
- The user has since physically confirmed `M-s-k`, `s-,`, and `s-.` in the
  running UI. Other required Super aliases still need desktop verification.
- **Removal:** expose `QTextEdit#textCursor/#setTextCursor` and named cursor
  operation/mode enums in qt, then translate each core character column to its
  UTF-16 offset and set the native cursor directly.

## Disabling Qt text wrapping

- **Location:** `lib/roded/frontends/qt/editor_pane.rb`.
- **Observed binding:** qt 0.1.9 exposes `QTextEdit#setLineWrapMode(int)` but
  generates no `QTextEdit::LineWrapMode` enum names.
- **Reproducer:** `Qt::QTextEdit.constants.grep(/NoWrap|WidgetWidth/)` is empty;
  `/usr/include/qt6/QtWidgets/qtextedit.h` defines `NoWrap` first in the enum.
- **Workaround:** pass its public value `0` and render the body with HTML
  `white-space: pre`; a real offscreen widget exposes horizontal scrolling for a
  300-character line and scrolls its caret into view.
- **Removal:** generate the `QTextEdit::LineWrapMode` constants in qt and use
  `QTextEdit::NoWrap` instead of the numeric enum value.

## Disabling the native text context menu

- **Location:** `lib/roded/frontends/qt/editor_pane.rb`.
- **Observed behavior:** `QTextEdit` defaults to `DefaultContextMenu`; the
  keyboard Menu event opened native Copy/Select All actions instead of reaching
  Roded's project/buffer picker bindings.
- **Workaround:** set the widget's public `contextMenuPolicy` property to
  `Qt::NoContextMenu`. The Qt key translator still routes Menu and Alt+Menu.
- **Verification:** the offscreen widget reports property value `NoContextMenu`;
  `spec/qt_shortcut_routing_spec.rb` checks both Menu key routes.
- **Removal:** none; the Qt binding exposes the needed API and enum.
