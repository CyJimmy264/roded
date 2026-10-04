# Qt rendering direction, informed by KWrite sources

The current evidence points to our presentation path as a problem; it does not
establish that Qt itself cannot meet the input-latency target. QPlainTextEdit is
already used by Roded. However, our renderer inserts HTML into QTextDocument
blocks to represent the caret, current line, selection and search highlights.
Moving point therefore changes document formatting and replaces block contents.
Changes involving more than 64 rows rebuild the whole document. Each pane owns a
separate native document. The dispatcher also waits for a 12 ms timer tick.

The existing reset benchmarks explicitly drain that dispatcher, so they exclude
this timer, real keyboard delivery and the desktop compositor. They must not be
used as evidence that the running frontend has reached VS Code-like latency.

## What KWrite actually uses

Read from the KDE source mirrors on 2026-10-04:

- Kate/KWrite revision `8b4c8821989bfaf08cd549e362b27fc9aa42d68e`.
- KTextEditor revision `f4d7c6ad488332e459bdd78284681677166b5f19`.

KWrite's entry point starts the shared Kate application in KWrite mode. Its text
views come from KTextEditor, rather than a standard QPlainTextEdit containing
HTML. See [KWrite main.cpp](https://github.com/KDE/kate/blob/8b4c8821989bfaf08cd549e362b27fc9aa42d68e/apps/kwrite/main.cpp)
and the [shared view manager](https://github.com/KDE/kate/blob/8b4c8821989bfaf08cd549e362b27fc9aa42d68e/apps/lib/kateviewmanager.cpp).

`KateViewInternal` is a QWidget. Its cursor update avoids redundant work,
tags the old row and tags the new row when it differs. Its paint handler derives
the line interval from the damaged rectangle and renders through QPainter.
See [view implementation](https://github.com/KDE/ktexteditor/blob/f4d7c6ad488332e459bdd78284681677166b5f19/src/view/kateviewinternal.cpp#L2625)
and [paint handler](https://github.com/KDE/ktexteditor/blob/f4d7c6ad488332e459bdd78284681677166b5f19/src/view/kateviewinternal.cpp#L3812).

`KateLayoutCache` retains line layouts, reuses view entries when scrolling and
tracks dirty layouts. `KateRenderer` uses QTextLayout with format ranges and
draws caret shapes separately with QPainter. These are architectural observations,
not measured KWrite latency or proof that every KWrite operation is cheap.
See [layout cache](https://github.com/KDE/ktexteditor/blob/f4d7c6ad488332e459bdd78284681677166b5f19/src/render/katelayoutcache.cpp#L134)
and [renderer](https://github.com/KDE/ktexteditor/blob/f4d7c6ad488332e459bdd78284681677166b5f19/src/render/katerenderer.cpp#L954).

## Options worth comparing

| Option | Benefit to investigate | Work and limitations |
| --- | --- | --- |
| QPlainTextEdit with native decorations | Move caret/selection/current-line styling out of document HTML; keep native text layout | Ruby bindings need the necessary APIs; block caret and per-view state need separate treatment |
| Own Qt view using QPainter/QTextLayout | Cache visible line layouts, share core text across panes, repaint only damaged areas | Implement hit testing, scrolling, Unicode layout, IME, accessibility and selection; many small Ruby/native calls may erase the gain |
| Embed KTextEditor or Scintilla | Reuse a mature native editing component | Add bindings/dependencies and reconcile its document, undo and selection ownership with Roded's core |
| WebView with Monaco | Reuse an established browser editor engine | Requires a document/command bridge and another runtime; does not by itself remove core-side blocking work |

QPlainTextEdit already exposes temporary selections, and Qt documents its plain
layout as intended for large text documents. See [Qt API](https://doc.qt.io/qt-6/qplaintextedit.html).
The other component interfaces are documented by
[KTextEditor](https://api.kde.org/ktexteditor-module.html),
[Scintilla](https://www.scintilla.org/ScintillaDoc.html) and
[Monaco](https://github.com/microsoft/monaco-editor).

## Next evidence needed

First compare native cursor movement against our HTML cursor path on the same
1500/10,000-line fixtures, font, viewport and paint pumping. Trace the normal
key-to-core, core-to-dispatcher and dispatcher-to-paint phases separately. A
shared snapshot or changed QTextDocument value is not proof of a visible frame.

Then prototype native decorations and, if necessary, a cached visible-line view.
Check Unicode/tabs/EOL caret, selection/search, independent split views, scrolling,
IME and actual frames before replacing the production frontend. A WebView remains
an alternative to benchmark, not a performance conclusion based on its name.

Ruby lexical work is a separate measured bottleneck: the isolated 10,000-line
probe spent about 244 ms in Prism.lex and 560 ms producing spans. It now runs in a
child interpreter after edits to documents of at least 1500 rows. Request
coalescing and revision checks protect input from stale results; changed rows
temporarily lose coloring while unchanged rows retain their previous decoration.
Final multiline context is restored by the complete lexer. This improves text
response but does not make first loading, lexical CPU time or large Qt formatting
updates disappear. Foreground and color-settling times must be reported separately.
