#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "--inside-xvfb" ]]; then
  exec xvfb-run -a -s "-screen 0 1280x800x24" "$0" --inside-xvfb
fi

for dependency in bundle xdotool import cmp seq; do
  command -v "$dependency" >/dev/null || {
    printf 'Missing required command: %s\n' "$dependency" >&2
    exit 1
  }
done

smoke_dir=$(mktemp -d /tmp/roded-qt-scale.XXXXXX)
export QT_QPA_PLATFORM=xcb
export XDG_CONFIG_HOME="$smoke_dir/config"
export RODED_LOG_PATH="$smoke_dir/roded.log"
export RODED_LOG_LEVEL=DEBUG
mkdir -p "$XDG_CONFIG_HOME"

scale_file="$smoke_dir/large.txt"
seq -f 'line %05g' 1 10000 > "$scale_file"
cp "$scale_file" "$smoke_dir/expected.txt"
paths=()
for index in $(seq 1 30); do
  buffer_path="$smoke_dir/buffer-$index.txt"
  printf 'buffer %s\n' "$index" > "$buffer_path"
  paths+=("$buffer_path")
done
paths+=("$scale_file")

app_pid=
cleanup() {
  if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then
    kill "$app_pid" 2>/dev/null || true
    wait "$app_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT

bundle exec bin/roded --frontend qt "${paths[@]}" > "$smoke_dir/app.out" 2>&1 &
app_pid=$!
window_id=
for attempt in $(seq 1 300); do
  window_id=$(xdotool search --onlyvisible --name '^Roded$' 2>/dev/null | head -n 1 || true)
  [[ -n "$window_id" ]] && break
  sleep 0.1
done
if [[ -z "$window_id" ]]; then
  cat "$smoke_dir/app.out"
  exit 1
fi

sleep 1
import -window "$window_id" "$smoke_dir/10k-lines-top.png"
xdotool windowfocus --sync "$window_id"
xdotool key --clearmodifiers Super_L+comma
xdotool key --clearmodifiers Super_L+period
sleep 1
xdotool key --clearmodifiers ctrl+n
xdotool key --clearmodifiers alt+shift+period
xdotool windowsize "$window_id" 960 540
sleep 3
xdotool windowfocus --sync "$window_id"
xdotool key --clearmodifiers ctrl+x
sleep 0.2
xdotool key --clearmodifiers ctrl+s
for attempt in $(seq 1 50); do
  cmp -s "$scale_file" "$smoke_dir/expected.txt" && break
  sleep 0.1
done
if ! cmp -s "$scale_file" "$smoke_dir/expected.txt"; then
  printf 'Qt changed the 10,000-line file during navigation/save\n' >&2
  exit 1
fi
import -window "$window_id" "$smoke_dir/10k-lines-30-buffers.png"
xdotool windowfocus --sync "$window_id"
xdotool key --clearmodifiers ctrl+x
sleep 0.2
xdotool key --clearmodifiers ctrl+c

for attempt in $(seq 1 300); do
  app_state=$(ps -o stat= -p "$app_pid" || true)
  [[ -z "$app_state" || "$app_state" == Z* ]] && break
  sleep 0.1
done
if [[ -n "$app_state" && "$app_state" != Z* ]]; then
  printf 'Qt scale process did not exit (state %s)\n' "$app_state" >&2
  exit 1
fi
wait "$app_pid"
app_pid=

previous_count=$(rg -Fc 'event received: key {key: "s-,"' "$RODED_LOG_PATH")
next_count=$(rg -Fc 'event received: key {key: "s-."' "$RODED_LOG_PATH")
if [[ "$previous_count" -lt 1 || "$next_count" -lt 1 ]] || ! rg -Fq 'event received: key {key: "M->"' "$RODED_LOG_PATH" ||
  ! rg -Fq 'event received: resize' "$RODED_LOG_PATH" ||
  ! rg -Fq 'event received: key {key: "C-s"' "$RODED_LOG_PATH" ||
  rg -Fq 'Editor runtime failed' "$RODED_LOG_PATH"; then
  printf 'Qt scale input/resize check failed: prev=%s next=%s; files=%s\n' \
    "$previous_count" "$next_count" "$smoke_dir" >&2
  exit 1
fi

printf 'Qt scale smoke passed: 10,000 lines, 31 buffers, Super+,/Super+., M->, C-x C-s and window resize; artifacts=%s\n' \
  "$smoke_dir"
