# Repository Guidelines

## Project Structure & Module Organization
- `lib/roded` holds the core editor classes (Application, Buffer, Window, StatusBar, Minibuffer, Event/Command, Logging); frontends live in `lib/roded/frontends` (currently curses).
- Binaries: `bin/roded` entrypoint, `bin/console` for IRB sandboxing, `bin/setup` for bootstrapping.
- Tests sit in `spec` with shared config in `spec/spec_helper.rb`; default Rake task runs tests and lint.
- Packaging/metadata lives in `roded.gemspec`; docs in `docs/`; built gems accumulate in `pkg/`.

## Build, Test, and Development Commands
- `bin/setup` installs Bundler dependencies.
- `bundle exec rake` runs specs and RuboCop (default task).
- `bundle exec rspec` runs the test suite; `.rspec_status` tracks failures between runs.
- `bundle exec rubocop` enforces style (TargetRubyVersion 3.4, double-quoted strings).
- `bundle exec rake install` builds and installs the gem locally; `bin/roded` launches the curses UI (requires terminal curses support).

## Coding Style & Naming Conventions
- Ruby 3.4 syntax; prefer double-quoted strings; omit `# frozen_string_literal: true` headers.
- One top-level class/module per file under `lib/roded`, matching snake_case filenames.
- Class/module names PascalCase; methods/variables snake_case; constants SCREAMING_SNAKE_CASE.
- Keep concurrency interactions thread-safe (Application uses Queue + threads; curses frontend reads input via `IO.select`).

## Testing Guidelines
- Framework: RSpec; place specs alongside features in `spec/*_spec.rb`.
- Name examples with behavior statements (`it "renders buffer top line"`), avoiding brittle curses-terminal assertions.
- `spec/spec_helper.rb` must force Qt specs to `QT_QPA_PLATFORM=offscreen` and
  use a per-process `XDG_CONFIG_HOME` under the system temp directory, even if
  the caller has exported desktop Qt or user config settings. Live UI smoke
  checks run separately under Xvfb.
- Cover command routing and buffer mutations when adding features; use test doubles for frontends when possible.
- For Qt visual regressions, also run a live-widget smoke check modeled on the Qt gem's `examples/development_ordered_demos/02_live_layout_console.rb`: keep the `QApplication` and widgets referenced, perform widget changes on the GUI thread, and pump `QApplication.process_events` while the check runs. Verify the visible editor, caret/modeline, and scrolling (a changed `to_plain_text` value alone does not prove the frame updated); capture the UI in an isolated Xvfb session when a screenshot is useful. This is a diagnostic/test harness pattern, not a requirement to replace the application's event loop.

## Commit & Pull Request Guidelines
- Commit messages short, imperative, and scoped (`Add cursor redraw command`); reserve `--wip-- [skip ci]` only for temporary checkpoints.
- Rebase or squash noisy WIP commits before review; link issues in the message or PR description when relevant.
- PRs should describe intent, testing performed (`bundle exec rake`, manual TUI check), and any UI changes (screenshots/recordings welcome).
- Flag breaking changes (keybindings, file I/O) prominently and update docs/README if behavior shifts.
