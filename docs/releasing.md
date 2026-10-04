# Preparing a release

Release 0.2.0 targets Ruby 3.4.2+ on Linux. The tested environment uses curses
1.5.3, qt gem 0.2.0 and Qt Widgets 6.11.2. Bundler's lockfile records the exact
development dependencies; the gemspec records supported runtime constraints.

## Local preparation

Update `lib/roded/version.rb`, the path dependency in `Gemfile.lock` and CHANGELOG
together. Keep README, keybindings and current architecture documentation accurate.
Completed work plans and per-step journals belong in Git history. Keep useful
benchmark reports and raw provenance in the checkout; they are excluded from the gem.

```sh
bundle check
bundle exec rake release:check
bundle exec ruby script/curses_two_file_acceptance_smoke.rb
script/qt_two_file_acceptance_smoke.sh
xvfb-run -a -s '-screen 0 1280x800x24' bundle exec ruby benchmark/qt_horizontal_scroll_smoke.rb
```

`release:check` runs specs, RuboCop, builds `pkg/roded-VERSION.gem`, and verifies
the packaged files and extracted runtime in an isolated temporary directory.
It does not install into the user's gem home. The gem contains library sources,
`bin/roded`, README, CHANGELOG, license and maintained documentation; tests,
benchmarks, agent instructions/skills and development scripts stay in Git.
Documentation for benchmarks/live checks refers to the source checkout.

Live acceptance requires Xvfb, xdotool and ImageMagick for Qt, and PTY support
for curses. Run Xvfb checks sequentially with private XDG paths. Synthetic X11
Super-key delivery does not establish whether a desktop window manager intercepts
physical shortcuts; standard bindings and M-x remain available.

Inspect `git diff --check`, commit the release preparation and verify the working
tree is clean. Record the gem's SHA-256 beside the local package.

## Publication

Publishing is a separate release action: create an annotated `vVERSION` tag at
the checked release commit, push the commit/tag to the intended remotes, then
publish the verified gem to the gemspec's RubyGems host. The package requests
RubyGems MFA. Preparing or checking the package does not execute those actions.
Use the matching CHANGELOG section as the release notes.
