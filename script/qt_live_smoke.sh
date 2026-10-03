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

smoke_dir=$(mktemp -d /tmp/roded-qt-live-smoke.XXXXXX)
export QT_QPA_PLATFORM=xcb
export XDG_CONFIG_HOME="$smoke_dir/config"
export RODED_LOG_PATH="$smoke_dir/roded.log"
export RODED_LOG_LEVEL=DEBUG
mkdir -p "$XDG_CONFIG_HOME"
seq -f 'line %03g' 1 100 > "$smoke_dir/lines.txt"

app_pid=
cleanup() {
  if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then
    kill "$app_pid" 2>/dev/null || true
    wait "$app_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT

bundle exec bin/roded --frontend qt "$smoke_dir/lines.txt" >"$smoke_dir/app.out" 2>&1 &
app_pid=$!
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

# Wait for the initial core snapshot to reach the UI before synthesizing input.
sleep 1
xdotool windowfocus --sync "$window_id"
xdotool mousemove --window "$window_id" 120 100 click 1
sleep 0.3
xdotool key --clearmodifiers ctrl+n
sleep 1
import -window "$window_id" "$smoke_dir/after-ctrl-n.png"
xdotool mousemove --window "$window_id" 300 160 click 5
sleep 1
import -window "$window_id" "$smoke_dir/after-wheel.png"
xdotool key --clearmodifiers alt+shift+period
sleep 2
import -window "$window_id" "$smoke_dir/after-meta-end.png"
xdotool key --clearmodifiers ctrl+x ctrl+c
sleep 0.5

printf 'Qt live smoke screenshots and log: %s\n' "$smoke_dir"
printf 'Key events: '
rg -c 'event received: key' "$RODED_LOG_PATH"
printf 'Wheel events: '
rg -c 'event received: scroll_by' "$RODED_LOG_PATH"
