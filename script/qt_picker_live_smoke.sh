#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "--inside-xvfb" ]]; then
  exec xvfb-run -a -s "-screen 0 1280x800x24" "$0" --inside-xvfb
fi

for dependency in bundle xdotool import rg; do
  command -v "$dependency" >/dev/null || {
    printf 'Missing required command: %s\n' "$dependency" >&2
    exit 1
  }
done

smoke_dir=$(mktemp -d /tmp/roded-qt-picker-smoke.XXXXXX)
export QT_QPA_PLATFORM=xcb
export XDG_CONFIG_HOME="$smoke_dir/config"
export XDG_CACHE_HOME="$smoke_dir/cache"
export RODED_LOG_PATH="$smoke_dir/roded.log"
export RODED_LOG_LEVEL=DEBUG
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
source_path="$smoke_dir/source.txt"
printf 'picker smoke\n' > "$source_path"

app_pid=
cleanup() {
  if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then
    kill "$app_pid" 2>/dev/null || true
    wait "$app_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT

wait_for_picker_count() {
  local expected_count=$1
  local rendered_count=0
  for attempt in $(seq 1 100); do
    rendered_count=$(rg -c 'publish_ui_update: picker_render' "$RODED_LOG_PATH" || true)
    if [[ "$rendered_count" -ge "$expected_count" ]]; then
      sleep 0.5
      return
    fi
    sleep 0.1
  done
  printf 'Qt did not render picker number %s\n' "$expected_count" >&2
  exit 1
}

bundle exec bin/roded --frontend qt "$source_path" > "$smoke_dir/app.out" 2>&1 &
app_pid=$!
window_id=
for attempt in $(seq 1 100); do
  window_id=$(xdotool search --onlyvisible --name '^Roded$' 2>/dev/null | head -n 1 || true)
  [[ -n "$window_id" ]] && break
  sleep 0.1
done
if [[ -z "$window_id" ]]; then
  cat "$smoke_dir/app.out"
  exit 1
fi

sleep 1
xdotool windowfocus --sync "$window_id"
xdotool key --clearmodifiers Menu
wait_for_picker_count 1
import -window "$window_id" "$smoke_dir/project-picker.png"
xdotool key --clearmodifiers ctrl+g
sleep 0.3
xdotool key --clearmodifiers alt+Menu
wait_for_picker_count 2
import -window "$window_id" "$smoke_dir/buffer-picker.png"
xdotool key --clearmodifiers ctrl+g
sleep 0.3
xdotool windowfocus --sync "$window_id"
xdotool key --clearmodifiers ctrl+x
sleep 0.2
xdotool key --clearmodifiers ctrl+c
for attempt in $(seq 1 100); do
  app_state=$(ps -o stat= -p "$app_pid" || true)
  [[ -z "$app_state" || "$app_state" == Z* ]] && break
  sleep 0.1
done
if [[ -n "$app_state" && "$app_state" != Z* ]]; then
  printf 'Qt picker smoke did not exit after C-x C-c\n' >&2
  exit 1
fi
wait "$app_pid"
app_pid=

if [[ $(rg -c 'publish_ui_update: picker_render' "$RODED_LOG_PATH") -lt 2 ]] ||
  ! rg -Fq 'event received: key {key: "Menu"' "$RODED_LOG_PATH" ||
  ! rg -Fq 'event received: key {key: "M-Menu"' "$RODED_LOG_PATH" ||
  rg -Fq 'Editor runtime failed' "$RODED_LOG_PATH"; then
  printf 'Qt picker input or render check failed; artifacts=%s\n' "$smoke_dir" >&2
  exit 1
fi

printf 'Qt picker live smoke passed: project files, buffers, cancel and quit; artifacts=%s\n' \
  "$smoke_dir"
