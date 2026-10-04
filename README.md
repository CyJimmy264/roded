# Roded

Roded is a programmable editor and Ruby development environment. Its editor
core owns documents, edits, undo history, and window positions; curses and Qt
are two frontends to that shared core.

## Requirements and installation

- Ruby **3.4.2 or later** on Linux.
- Bundler and the dependencies in `Gemfile.lock`.
- A UTF-8 terminal for curses. Qt mode also needs the Qt 6 runtime and a working
  desktop display; see [Qt setup and verification](docs/qt-frontend.md).

From a checkout:

```sh
bin/setup
bundle exec bin/roded [file ...]
```

The default frontend is curses. To use the Qt desktop frontend:

```sh
bundle exec bin/roded --frontend qt [file ...]
```

Both frontends accept multiple file paths. Starting without paths opens the
writable `*scratch*` buffer. `C-x C-f` opens or creates a file buffer; `C-x C-s`
or `F7` saves it. A new file is written when saved, and Roded does not create
missing parent directories automatically. If a buffer has edits, closing it or
quitting offers save, discard, and cancel choices.

## Editing and windows

Roded uses Emacs-style, non-modal editing. Common keys include:

| Action | Keys |
| --- | --- |
| Move by character or line | `C-f` / `C-b`, `C-n` / `C-p`, or arrow keys |
| Start/end of line | `C-a` / `C-e` |
| Start/end of document | `M-<` / `M->` |
| Page up/down | `M-v` / `C-v`, or PageUp / PageDown |
| Undo / redo | `C-/`, `C-_`, `C-x u` / `C-?`, `C-c r d` |
| Open / save / save as | `C-x C-f` / `C-x C-s` / `C-x C-w` |
| Quit | `C-x C-c` |
| Cancel a prefix, prompt, or picker | `C-g` |

`Tab` indents by two spaces. Mark and region commands include `C-SPC` to set a
mark, `C-w` to cut, `M-w` to copy, and `C-y` to yank. `C-s` opens a line picker
for the current buffer; `M-x isearch-forward` and `M-x isearch-backward` search
text, `M-g g` goes to a line, and `M-%` starts query replace. Edits can be
undone independently in each buffer.

Buffers and editor windows are separate. Switch buffers with `C-x b` or
`C-x <left>` / `C-x <right>`. Split the active window with `C-x 2` (top and
bottom) or `C-x 3` (left and right); use `C-x o` to switch windows, `C-x 0` to
close the active window, and `C-x 1` to keep only it. A document may be shown in
more than one window; each view keeps its own cursor and scroll position.

The picker is available from `M-x` for commands, `C-x b` for buffers,
`C-x C-f` for paths, `C-s` for lines, and `M-y` for the kill ring. In a picker,
type to filter, use `C-n` / `C-p` or Up / Down to move, Enter to accept, and
`C-g` to cancel. `C-c p f` opens project or root files. `C-h b` displays the
active bindings; `M-x describe-bindings` provides the same command.

## Syntax modes and Ruby REPL

Filename-based modes provide syntax highlighting for Ruby, JSON, YAML, and
Markdown, with plain text as the fallback. The mode can also be changed through
the command picker. Highlighting is presentation only and does not alter the
buffer contents or undo history.

After edits in Ruby documents of 1500 or more rows, coloring runs in a separate
process. Text and the caret update immediately; changed rows regain their colors
when the current revision finishes. Initial coloring still runs synchronously.
See [Qt rendering alternatives and the KWrite source review](docs/qt-rendering-alternatives.md).

Open the in-process Ruby REPL with `C-c r r` or `M-x ruby-repl`. Enter Ruby in
`*ruby*`, run it with `C-c C-c`, and interrupt a running expression with
`C-c C-k`. `C-c C-p` and `C-c C-n` navigate REPL history. Results, output,
warnings, and exceptions appear in the REPL buffer; `exit` leaves the REPL
without quitting Roded.

The REPL exposes an `editor` object for inspecting snapshots and requesting
edits through the core event loop:

```ruby
editor.current_buffer
editor.buffers
editor.insert_text("hello")
editor.save_file("notes.txt")
editor.register_command("insert-greeting", binding: "C-c g") do |api|
  api.insert_text("Hello from Ruby")
end
```

Ruby code runs in the editor process with the current user's permissions. Run
only trusted code. Changes made through the editor API follow the normal undo,
readonly, modified-state, and multiple-view rules.

## Qt shortcuts and pointer input

The Qt editor routes text editing through the same core as curses. It supports
mouse caret placement and selection, wheel scrolling, and the system clipboard.
Use `C-S-c`, `C-S-x`, and `C-S-v` to copy, cut, and paste the selected text;
`C-v` remains page down. The `Menu` key opens the project/root file picker and
`M-Menu` opens the buffer picker. The native text context menu is disabled so
these keys and editor commands keep their normal routing.

On Linux, Qt maps `M-` to Alt and `s-` to Super. Roded provides aliases such as
`M-s-j` (save), `M-s-k` (kill buffer), `s-,` / `s-.` (previous / next buffer),
and `s-Left` / `s-Right` (resize the active split). A window manager can reserve
Super shortcuts before Qt receives them. See the full [keybinding reference](docs/keybindings.md)
for aliases, fallback bindings, and the tested limits.

## Configuration and development

An optional YAML keymap at `$XDG_CONFIG_HOME/roded/keymap.yml` overrides
individual bindings (`~/.config/roded/keymap.yml` when `XDG_CONFIG_HOME` is not
set). Each entry names a command type; custom command bindings can include a
command name:

```yaml
"C-c l":
  type: custom_command
  payload:
    name: select-current-line
```

Roded validates the file at startup and displays a warning if it cannot be
loaded. `C-h b` shows the resulting active keymap. See
[`docs/keybindings.md`](docs/keybindings.md) for the key names and available
commands.

Application diagnostics are written to `~/.cache/roded/roded.log` by default,
separately from minibuffer messages. Set `RODED_LOG_PATH` to choose another
file and `RODED_LOG_LEVEL=DEBUG` to include input/event details while debugging.

Run the automated checks with:

```sh
bundle exec rake
```

Long-document performance benchmarks (1500, 5000 and 10,000 lines) run separately:

```sh
bundle exec rake benchmark
```

They record operation latency, allocations and GC statistics in JSON, and can
compare an optimization against a saved baseline. See
[benchmark workloads, frontend measurements and comparison commands](docs/benchmarks.md).

The test suite uses offscreen Qt widgets for integration tests. Live frontend
smoke checks use a private PTY or Xvfb with private Qt config directories; they
do not need the user's desktop session. Current versions, commands, observations,
screenshots, and remaining environment-specific checks are recorded in
[`docs/working-editor-validation.md`](docs/working-editor-validation.md).

Roded's first working version does not include LSP, collaboration, Vim/Evil
mode, structural editing, folding, or a plugin framework. Other unimplemented
items remain roadmap work rather than advertised features.

## License

Copyright (C) 2025 Maksim Veynberg <mv@cj264.ru>

SPDX-License-Identifier: BSD-2-Clause

See `LICENSE`.
