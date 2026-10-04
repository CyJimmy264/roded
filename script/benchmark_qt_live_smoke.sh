#!/usr/bin/env bash
set -euo pipefail

# The benchmark's Qt adapter must also update visible widgets under real X11.
exec xvfb-run -a -s "-screen 0 1280x800x24" bundle exec ruby benchmark/qt_smoke.rb
