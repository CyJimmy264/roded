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
