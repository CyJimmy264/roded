#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "--inside-xvfb" ]]; then
  command -v xvfb-run >/dev/null || {
    printf 'Missing required command: xvfb-run\n' >&2
    exit 1
  }
  exec xvfb-run -a -s "-screen 0 1280x800x24" "$0" --inside-xvfb
fi

for dependency in alacritty bundle xdotool rg; do
  command -v "$dependency" >/dev/null || {
    printf 'Missing required command: %s\n' "$dependency" >&2
    exit 1
  }
done

repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repository"
smoke_dir=$(mktemp -d /tmp/roded-curses-xvfb.XXXXXX)
export XDG_CONFIG_HOME="$smoke_dir/config"
export XDG_CACHE_HOME="$smoke_dir/cache"
export XDG_RUNTIME_DIR="$smoke_dir/runtime"
export RODED_LOG_PATH="$smoke_dir/roded.log"
export RODED_LOG_LEVEL=DEBUG
export RODED_SMOKE_REPOSITORY="$repository"
export RODED_SMOKE_FILE="$smoke_dir/input.txt"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
printf 'one\ntwo\n' > "$RODED_SMOKE_FILE"

terminal_pid=
cleanup() {
  if [[ -n "$terminal_pid" ]] && kill -0 "$terminal_pid" 2>/dev/null; then
    kill "$terminal_pid" 2>/dev/null || true
    wait "$terminal_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT

LIBGL_ALWAYS_SOFTWARE=1 alacritty --config-file /dev/null -T Roded-Curses-Xvfb-Smoke \
  -o window.dimensions.columns=80 -o window.dimensions.lines=24 \
  -e env TERM=xterm-256color XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
  XDG_CACHE_HOME="$XDG_CACHE_HOME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
  RODED_LOG_PATH="$RODED_LOG_PATH" RODED_LOG_LEVEL=DEBUG \
  /bin/bash -c 'cd "$RODED_SMOKE_REPOSITORY" && exec bundle exec bin/roded "$RODED_SMOKE_FILE"' \
  > "$smoke_dir/alacritty.out" 2>&1 &
terminal_pid=$!

window_id=
for attempt in $(seq 1 100); do
  window_id=$(xdotool search --onlyvisible --name '^Roded-Curses-Xvfb-Smoke$' 2>/dev/null | head -n 1 || true)
  [[ -n "$window_id" ]] && break
  sleep 0.1
done
if [[ -z "$window_id" ]]; then
  cat "$smoke_dir/alacritty.out"
  exit 1
fi

wait_for_content() {
  local expected=$1
  printf '%s' "$expected" > "$smoke_dir/expected.txt"
  for attempt in $(seq 1 50); do
    if cmp -s "$RODED_SMOKE_FILE" "$smoke_dir/expected.txt"; then return 0; fi
    sleep 0.1
  done
  cat "$RODED_LOG_PATH"
  printf 'Curses keyboard smoke expected %q but got %q\n' \
    "$expected" "$(cat "$RODED_SMOKE_FILE")" >&2
  exit 1
}

sleep 1
xdotool windowfocus --sync "$window_id"
xdotool key --clearmodifiers ctrl+n
xdotool type --clearmodifiers XYZ
sleep 0.2
xdotool key --clearmodifiers ctrl+x
sleep 0.2
xdotool key --clearmodifiers ctrl+s
wait_for_content $'one\nXYZtwo\n'
xdotool windowfocus --sync "$window_id"
xdotool key --clearmodifiers ctrl+slash
sleep 0.3
xdotool key --clearmodifiers ctrl+x
sleep 0.2
xdotool key --clearmodifiers ctrl+s
wait_for_content $'one\ntwo\n'
xdotool windowfocus --sync "$window_id"
xdotool key --clearmodifiers ctrl+shift+slash
sleep 0.3
xdotool key --clearmodifiers ctrl+x
sleep 0.2
xdotool key --clearmodifiers ctrl+s
wait_for_content $'one\nXYZtwo\n'
rg -Fq 'next_event: read_key: "C-/"' "$RODED_LOG_PATH"
rg -Fq 'next_event: read_key: "C-?"' "$RODED_LOG_PATH"
xdotool key --clearmodifiers ctrl+x
sleep 0.2
xdotool key --clearmodifiers ctrl+c

for attempt in $(seq 1 50); do
  state=$(ps -o stat= -p "$terminal_pid" || true)
  [[ -z "$state" || "$state" == Z* ]] && break
  sleep 0.1
done
state=$(ps -o stat= -p "$terminal_pid" || true)
if [[ -n "$state" && "$state" != Z* ]]; then
  printf 'Curses terminal did not exit (state %s)\n' "$state" >&2
  exit 1
fi
wait "$terminal_pid"
terminal_pid=

printf 'curses Xvfb/Alacritty smoke passed (Ctrl+N, type/save, Ctrl+/, undo, Ctrl+?, redo, clean exit); log=%s\n' \
  "$RODED_LOG_PATH"
