#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "--inside-xvfb" ]]; then
  exec xvfb-run -a -s "-screen 0 1280x800x24" "$0" --inside-xvfb
fi

for dependency in bundle xdotool import; do
  command -v "$dependency" >/dev/null || {
    printf 'Missing required command: %s\n' "$dependency" >&2
    exit 1
  }
done

smoke_dir=$(mktemp -d /tmp/roded-qt-final-newline.XXXXXX)
export QT_QPA_PLATFORM=xcb
export XDG_CONFIG_HOME="$smoke_dir/config"
export RODED_LOG_PATH="$smoke_dir/roded.log"
export RODED_LOG_LEVEL=DEBUG
mkdir -p "$XDG_CONFIG_HOME"
file="$smoke_dir/final-newline.txt"
printf 'alpha\n' > "$file"

bundle exec bin/roded --frontend qt "$file" >"$smoke_dir/app.out" 2>&1 &
app_pid=$!
cleanup() {
  if kill -0 "$app_pid" 2>/dev/null; then
    kill "$app_pid" 2>/dev/null || true
    wait "$app_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT

window_id=
for attempt in $(seq 1 100); do
  window_id=$(xdotool search --onlyvisible --name '^Roded$' 2>/dev/null | head -n 1 || true)
  if [[ -n "$window_id" ]]; then break; fi
  sleep 0.1
done
if [[ -z "$window_id" ]]; then
  cat "$smoke_dir/app.out"
  exit 1
fi

sleep 0.5
xdotool windowfocus --sync "$window_id"
xdotool mousemove --window "$window_id" 120 80 click 1
xdotool key --clearmodifiers alt+shift+period
sleep 0.3
import -window "$window_id" "$smoke_dir/final-newline-caret.png"
xdotool type --clearmodifiers x
xdotool key --clearmodifiers space
xdotool key --clearmodifiers ctrl+x
sleep 0.2
xdotool key --clearmodifiers ctrl+s

for attempt in $(seq 1 50); do
  if ruby -e 'exit(File.binread(ARGV.fetch(0)) == "alpha\nx " ? 0 : 1)' "$file"; then break; fi
  sleep 0.1
done
if ! ruby -e 'exit(File.binread(ARGV.fetch(0)) == "alpha\nx " ? 0 : 1)' "$file"; then
  printf 'Final-newline editing or Qt Space input produced unexpected text:\n' >&2
  ruby -e 'p File.binread(ARGV.fetch(0))' "$file" >&2
  exit 1
fi

xdotool key --clearmodifiers ctrl+x
sleep 0.2
xdotool key --clearmodifiers ctrl+c
for attempt in $(seq 1 50); do
  app_state=$(ps -o stat= -p "$app_pid" || true)
  [[ -z "$app_state" || "$app_state" == Z* ]] && break
  sleep 0.1
done
if [[ -n "$app_state" && "$app_state" != Z* ]]; then
  printf 'Qt final-newline smoke did not exit after C-x C-c\n' >&2
  exit 1
fi
wait "$app_pid"
app_pid=

printf 'Qt final-newline editing and Space input passed; screenshot and log: %s\n' "$smoke_dir"
