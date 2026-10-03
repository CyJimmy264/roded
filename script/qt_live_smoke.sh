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
seq -f 'line %03g' 1 100 | awk 'NR == 3 { print "" } { print }' > "$smoke_dir/lines.txt"

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
xdotool key --clearmodifiers alt+shift+comma
xdotool key --clearmodifiers ctrl+n
sleep 1
import -window "$window_id" "$smoke_dir/after-ctrl-n.png"
xdotool windowfocus --sync "$window_id"
xdotool type --clearmodifiers X
xdotool key --clearmodifiers ctrl+x
sleep 0.4
xdotool key --clearmodifiers ctrl+s
saved_line=
for attempt in $(seq 1 50); do
  saved_line=$(sed -n '2p' "$smoke_dir/lines.txt")
  [[ "$saved_line" == "Xline 002" ]] && break
  sleep 0.1
done
if [[ "$saved_line" != "Xline 002" ]]; then
  printf 'Unexpected saved line: %s\n' "$saved_line" >&2
  exit 1
fi
sleep 0.5
import -window "$window_id" "$smoke_dir/after-edit-save.png"
xdotool windowfocus --sync "$window_id"
xdotool mousemove --window "$window_id" 30 64 click 1
sleep 0.5
import -window "$window_id" "$smoke_dir/after-blank-line-caret.png"
xdotool windowfocus --sync "$window_id"
xdotool mousemove --window "$window_id" 30 100 mousedown 1
xdotool mousemove --sync --window "$window_id" 90 100
xdotool mouseup 1
xdotool key --clearmodifiers ctrl+shift+c
sleep 0.5
import -window "$window_id" "$smoke_dir/after-mouse-selection-copy.png"
xdotool mousemove --window "$window_id" 300 160 click 5
sleep 1
import -window "$window_id" "$smoke_dir/after-wheel.png"
xdotool windowfocus --sync "$window_id"
xdotool key --clearmodifiers alt+shift+period
sleep 2
import -window "$window_id" "$smoke_dir/after-meta-end.png"
xdotool windowfocus --sync "$window_id"
xdotool key --clearmodifiers ctrl+x
sleep 0.4
xdotool key --clearmodifiers 3
sleep 1
import -window "$window_id" "$smoke_dir/after-split.png"
xdotool windowfocus --sync "$window_id"
xdotool key --clearmodifiers Menu
sleep 0.5
xdotool key --clearmodifiers ctrl+g
sleep 0.3
xdotool key --clearmodifiers alt+Menu
sleep 0.5
xdotool key --clearmodifiers ctrl+g
sleep 0.3
xdotool windowfocus --sync "$window_id"
xdotool mousemove --window "$window_id" 300 100 click 1
xdotool key --clearmodifiers Super_L+Right
sleep 1
import -window "$window_id" "$smoke_dir/after-super-right.png"
xdotool windowfocus --sync "$window_id"
xdotool mousemove --window "$window_id" 300 100 click 1
xdotool key --clearmodifiers Super_L+Left
sleep 1
import -window "$window_id" "$smoke_dir/after-super-resize.png"
xdotool windowfocus --sync "$window_id"
xdotool mousemove --window "$window_id" 300 100 click 1
xdotool key --clearmodifiers ctrl+x
sleep 0.4
xdotool key --clearmodifiers ctrl+c
app_state=$(ps -o stat= -p "$app_pid" || true)
for attempt in $(seq 1 50); do
  app_state=$(ps -o stat= -p "$app_pid" || true)
  [[ -z "$app_state" || "$app_state" == Z* ]] && break
  sleep 0.1
done
if [[ -n "$app_state" && "$app_state" != Z* ]]; then
  printf 'Qt app did not exit after C-x C-c (state %s)\n' "$app_state" >&2
  exit 1
fi
wait "$app_pid"
app_pid=

# Exercise the real no-argument startup path, which creates an empty *scratch*.
export RODED_LOG_PATH="$smoke_dir/scratch.log"
bundle exec bin/roded --frontend qt >"$smoke_dir/scratch.out" 2>&1 &
app_pid=$!
scratch_window_id=
for attempt in $(seq 1 100); do
  scratch_window_id=$(xdotool search --onlyvisible --name '^Roded$' 2>/dev/null | head -n 1 || true)
  if [[ -n "$scratch_window_id" ]]; then break; fi
  sleep 0.1
done
if [[ -z "$scratch_window_id" ]]; then
  cat "$smoke_dir/scratch.out"
  exit 1
fi
sleep 1
import -window "$scratch_window_id" "$smoke_dir/empty-scratch.png"
xdotool windowfocus --sync "$scratch_window_id"
xdotool mousemove --window "$scratch_window_id" 30 30 click 1
xdotool key --clearmodifiers ctrl+x
sleep 0.3
xdotool key --clearmodifiers ctrl+c
for attempt in $(seq 1 50); do
  app_state=$(ps -o stat= -p "$app_pid" || true)
  [[ -z "$app_state" || "$app_state" == Z* ]] && break
  sleep 0.1
done
if [[ -n "$app_state" && "$app_state" != Z* ]]; then
  printf 'Qt scratch startup did not exit after C-x C-c (state %s)\n' "$app_state" >&2
  exit 1
fi
wait "$app_pid"
app_pid=
if ! rg -q 'Application initialized' "$smoke_dir/scratch.log" ||
  ! rg -q 'event received: key \{key: "C-c"' "$smoke_dir/scratch.log"; then
  printf 'Qt no-argument startup did not route keyboard input\n' >&2
  exit 1
fi

printf 'Qt live smoke screenshots and log: %s\n' "$smoke_dir"
printf 'Empty scratch startup and keyboard quit: passed\n'
printf 'Key events: '
rg -c 'event received: key' "$RODED_LOG_PATH"
printf 'Wheel events: '
rg -c 'event received: scroll_by' "$RODED_LOG_PATH"
printf 'Mouse selection events: '
mouse_selection_events=$(rg -c 'event received: mouse_selection' "$RODED_LOG_PATH" || true)
if [[ "$mouse_selection_events" -lt 5 ]] || ! rg -q 'event received: mouse_selection .*mark: \{row:' "$RODED_LOG_PATH"; then
  printf 'Expected mouse caret and drag-selection events, got %s\n' "$mouse_selection_events" >&2
  exit 1
fi
printf '%s\n' "$mouse_selection_events"
if ! rg -q 'event received: mouse_selection \{point: \{row: 2, col: 0\}' "$RODED_LOG_PATH"; then
  printf 'Qt click did not place the caret on the empty third line\n' >&2
  exit 1
fi
if ! rg -q 'event received: key \{key: "Menu"' "$RODED_LOG_PATH" ||
  ! rg -q 'event received: key \{key: "M-Menu"' "$RODED_LOG_PATH" ||
  [[ $(rg -c 'broadcast_command: picker_render' "$RODED_LOG_PATH") -lt 2 ]]; then
  printf 'Qt Menu/Alt+Menu did not open both core pickers\n' >&2
  exit 1
fi
printf 'Menu shortcuts: project_files, switch_buffer\n'
