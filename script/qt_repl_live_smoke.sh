#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "--inside-xvfb" ]]; then
  exec xvfb-run -a -s "-screen 0 1280x800x24" "$0" --inside-xvfb
fi

for dependency in bundle xdotool import xsel; do
  command -v "$dependency" >/dev/null || {
    printf 'Missing required command: %s\n' "$dependency" >&2
    exit 1
  }
done

smoke_dir=$(mktemp -d /tmp/roded-qt-repl-smoke.XXXXXX)
export QT_QPA_PLATFORM=xcb
export XDG_CONFIG_HOME="$smoke_dir/config"
export XDG_CACHE_HOME="$smoke_dir/cache"
export RODED_LOG_PATH="$smoke_dir/roded.log"
export RODED_LOG_LEVEL=DEBUG
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
source_path="$smoke_dir/source.txt"
clipboard_path="$smoke_dir/clipboard.txt"
expected_paste_path="$smoke_dir/expected-after-paste.txt"
printf 'unchanged\n' > "$source_path"
printf 'pasted\ntext' > "$clipboard_path"
printf 'pasted\ntextunchanged\n' > "$expected_paste_path"
xsel --clipboard --input < "$clipboard_path" > "$smoke_dir/xsel.out" 2>&1 &
clipboard_pid=$!

app_pid=
cleanup() {
  if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then
    kill "$app_pid" 2>/dev/null || true
    wait "$app_pid" 2>/dev/null || true
  fi
  if [[ -n "${clipboard_pid:-}" ]] && kill -0 "$clipboard_pid" 2>/dev/null; then
    kill "$clipboard_pid" 2>/dev/null || true
    wait "$clipboard_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT

wait_for_log() {
  local entry=$1
  for attempt in $(seq 1 100); do
    rg -Fq "$entry" "$RODED_LOG_PATH" && return
    sleep 0.1
  done
  printf 'Qt REPL smoke did not observe log entry: %s\n' "$entry" >&2
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
xdotool key --clearmodifiers ctrl+shift+v
sleep 0.3
xdotool key --clearmodifiers ctrl+x
sleep 0.2
xdotool key --clearmodifiers ctrl+s
for attempt in $(seq 1 50); do
  cmp -s "$source_path" "$expected_paste_path" && break
  sleep 0.1
done
if ! cmp -s "$source_path" "$expected_paste_path"; then
  printf 'Qt live clipboard paste produced unexpected contents; artifacts=%s\n' "$smoke_dir" >&2
  exit 1
fi
xdotool key --clearmodifiers ctrl+slash
sleep 0.2
xdotool key --clearmodifiers ctrl+x
sleep 0.2
xdotool key --clearmodifiers ctrl+s
for attempt in $(seq 1 50); do
  [[ "$(cat "$source_path")" == "unchanged" ]] && break
  sleep 0.1
done
if [[ "$(cat "$source_path")" != "unchanged" ]]; then
  printf 'Qt live paste was not undone in one edit; artifacts=%s\n' "$smoke_dir" >&2
  exit 1
fi

xdotool key --clearmodifiers ctrl+c
sleep 0.2
xdotool key --clearmodifiers r
sleep 0.2
xdotool key --clearmodifiers r
sleep 2
import -window "$window_id" "$smoke_dir/repl-open.png"
xdotool type --clearmodifiers --delay 20 '40 + 2'
xdotool key --clearmodifiers ctrl+c
sleep 0.2
xdotool key --clearmodifiers ctrl+c
wait_for_log 'event received: repl_result {stdout: "", stderr: "", result: "42"}'
xdotool type --clearmodifiers --delay 10 'loop { sleep 0.01 }'
xdotool key --clearmodifiers ctrl+c
sleep 0.2
xdotool key --clearmodifiers ctrl+c
sleep 0.3
xdotool key --clearmodifiers ctrl+c
sleep 0.2
xdotool key --clearmodifiers ctrl+k
wait_for_log 'event received: repl_result {stdout: "", stderr: "", error: "Interrupt"}'

xdotool type --clearmodifiers --delay 20 '1 + 1'
xdotool key --clearmodifiers ctrl+c
sleep 0.2
xdotool key --clearmodifiers ctrl+c
wait_for_log 'event received: repl_result {stdout: "", stderr: "", result: "2"}'
sleep 0.5
import -window "$window_id" "$smoke_dir/repl-interrupt-recovered.png"

xdotool key --clearmodifiers ctrl+x
sleep 0.2
xdotool key --clearmodifiers ctrl+c
wait_for_log 'publish_ui_update: minibuffer_render'
xdotool type --clearmodifiers d
xdotool key --clearmodifiers Return
for attempt in $(seq 1 100); do
  app_state=$(ps -o stat= -p "$app_pid" || true)
  [[ -z "$app_state" || "$app_state" == Z* ]] && break
  sleep 0.1
done
if [[ -n "$app_state" && "$app_state" != Z* ]]; then
  printf 'Qt REPL smoke did not exit after discarding its modified buffer\n' >&2
  exit 1
fi
wait "$app_pid"
app_pid=

if [[ "$(cat "$source_path")" != "unchanged" ]] || rg -Fq 'Editor runtime failed' "$RODED_LOG_PATH"; then
  printf 'Qt REPL smoke changed the source file or failed the editor runtime\n' >&2
  exit 1
fi

printf 'Qt live smoke passed: clipboard paste/undo, REPL interrupt/recovery, discard and quit; artifacts=%s\n' \
  "$smoke_dir"
