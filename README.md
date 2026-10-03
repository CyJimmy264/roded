# Roded

Roded (Ruby Object-oriented Development Environment eDitor) is a programmable
editor and development environment in Ruby. The long-term goal is an editor that
is fully scriptable from inside and outside (like Emacs with Elisp), but with
Ruby as the extension language and a clean, frontend-agnostic core.

## Direction

- **Frontend-agnostic core:** multiple frontends should exist (terminal, GUI,
  web-based) with no hard limit on how many.
- **Fully programmable:** the editor itself and all extensions are written in
  Ruby and can be modified live.
- **More than an editor:** intended to be a complete interactive development
  environment with automation, tooling integration, and collaborative workflows.

## Current State

- Working curses frontend with a buffer model and minibuffer.
- Keymap support with configurable bindings.
- File open/save and basic editing commands.
- Logging to `~/.cache/roded/roded.log`.

## Getting Started

```bash
bin/setup
bundle exec bin/roded
```

## Configuration

Keymap is loaded from `~/.config/roded/keymap.yml` if present. Example:

```yaml
"C-x C-c":
  type: quit
"M-x":
  type: start_command
```

## Ruby REPL

Open the in-process REPL with `C-c r r` or `M-x ruby-repl`. Type Ruby into
`*ruby*`, run the current input with `C-c C-c`, interrupt a running expression
with `C-c C-k`, and browse command history with `C-c C-p` / `C-c C-n`. Input may
span multiple lines. Results, `puts` / `print`, `$stdout` / `$stderr` writes,
`warn`, and exceptions appear in the REPL buffer; `exit` closes the interaction
without quitting Roded.

The `editor` object in the REPL exposes a narrow API for inspecting immutable
snapshots and changing the live editor through its core event loop:

```ruby
editor.current_buffer
editor.buffers
editor.insert_text("hello")
editor.save_file("notes.txt")
editor.register_command("insert-greeting", binding: "C-c g") do |api|
  api.insert_text("Hello from Ruby")
end
```

Commands registered this way are available from `M-x` and their optional key
binding. Ruby expressions run inside the editor process with the current user's
permissions. Run only trusted code. The API routes editor mutations through the
core so normal undo, readonly, modified-state, and view-position rules apply.

## License

Copyright (C) 2025 Maksim Veynberg <mv@cj264.ru>

SPDX-License-Identifier: BSD-2-Clause

See `LICENSE`.
