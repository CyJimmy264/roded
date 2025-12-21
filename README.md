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

## License

Copyright (C) 2025 Maksim Veynberg <mv@cj264.ru>

SPDX-License-Identifier: BSD-2-Clause

See `LICENSE`.
