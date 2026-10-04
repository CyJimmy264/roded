# Qt frontend

Roded 0.2.0 uses the Ruby `qt` gem 0.2.x and Qt 6 Widgets on Linux.
The tested development environment uses Ruby 3.4.2, qt 0.2.0 and Qt Widgets 6.11.2;
live checks use XCB on a private Xvfb. A desktop launch needs a working display
and the Qt runtime required by the installed gem.

```sh
bin/setup
bundle exec bin/roded --frontend qt [file ...]
```

No local absolute path to the Qt source checkout is required. When adding an
API call, inspect/probe the installed gem's generated Ruby/native bindings:
a C++ Qt method is not necessarily exposed by this Ruby binding.

## Presentation and input

Each editor pane retains a read-only, no-wrap QPlainTextEdit document. Core text
and token spans are shared immutable snapshot data; native documents are per pane.
Changes update affected blocks, structural edits use edit blocks, and changes to
more than 64 rows rebuild the document. Plain panes copy as plain text.
Within-row caret-only movement on unchanged, unselected text updates the old/new
character formats without replacing the row. Other overlays use block HTML.

Core columns count Unicode codepoints; Qt offsets count UTF-16 units with expanded
tabs. QtCursorMapper/QtDocumentIndex translate positions in both directions,
including blank rows, end-of-line caret cells, combining marks and surrogate pairs.
The current row has a full-width background and a contrasting block caret.
Mouse press/drag/release hit testing produces core point/mark events.

QtTextEditor intercepts native editing and routes keys through the shared core.
Native undo and the text context menu are disabled. Clipboard reads/writes use
QApplication.clipboard. Alt represents Emacs Meta; Qt MetaModifier represents
Super on Linux. Split sizes reflect the core split tree and ratios.
Native close can be rejected while the core offers save/discard/cancel.

## Scheduling and scrolling

Widgets and callbacks run on the GUI thread. QtUiDispatcher coalesces pending
updates, preserves explicit refresh requests and wakes through a queued native
single-shot call. There is no periodic idle polling timer.
QtEventLoop releases Ruby's GVL around QApplication.exec so core/input/highlighter
threads can run between GUI callbacks; see [adaptations](qt-workarounds.md).

Scroll restoration uses one connected single-shot timer per pane. When rendering,
only Roded's horizontal feedback is suspended: native valueChanged signals must
reach Qt so unchanged neighboring rows scroll with the current row. The settled
origin is reported to core; intermediate programmatic origins are suppressed.

Fusion is the default style because Breeze's Alt mnemonic handling caused costly
viewport repainting in measurements. Explicit QT_STYLE_OVERRIDE is respected.
The existing renderer remains in use; [KWrite research](qt-rendering-alternatives.md)
is retained for future decisions supported by measurements or concrete features.

## Regression checks

The checkout's specs force QT_QPA_PLATFORM=offscreen and private XDG config.
Standalone probes need private config too. Live checks run under private Xvfb:

```sh
script/qt_live_smoke.sh
script/qt_two_file_acceptance_smoke.sh
RODED_BENCHMARK_PROFILE=ruby script/benchmark_qt_live_smoke.sh
xvfb-run -a -s '-screen 0 1280x800x24' bundle exec ruby benchmark/qt_horizontal_scroll_smoke.rb
```

Retain QApplication/widgets and pump events on the GUI thread for live-widget
checks. Inspect visible caret, row background, modeline and scrolling, not only
native document contents. The horizontal check compares neighboring-row X11
pixels before/after movement and against a complete viewport repaint.
Manual event pumping cannot establish native-loop scheduling; use the native
[latency harness](benchmarks.md) or `benchmark/qt_event_loop_probe.rb` for that.

Xvfb proves synthetic X11 delivery. A desktop window manager may intercept
physical Super shortcuts; retain the standard bindings/M-x fallbacks.
New binding adaptations belong in the Qt adapter, with version/API evidence,
lifetime handling, a reproducer and regression coverage. Do not patch the
installed gem or an unrelated source checkout as an implicit build step.
