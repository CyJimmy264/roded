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

wait_for_app_exit() {
  for attempt in $(seq 1 50); do
    app_state=$(ps -o stat= -p "$app_pid" || true)
    [[ -z "$app_state" || "$app_state" == Z* ]] && break
    sleep 0.1
  done
  if [[ -n "$app_state" && "$app_state" != Z* ]]; then
    printf 'Qt app did not exit after close decision (state %s)\n' "$app_state" >&2
    exit 1
  fi
  wait "$app_pid"
  app_pid=
}

run_close_prompt_smoke() {
  local choice=$1 expected_text=$2
  local close_path="$smoke_dir/close-$choice.txt"
  local close_log="$smoke_dir/close-$choice.log"
  local close_window_id=
  printf 'original\n' > "$close_path"
  export RODED_LOG_PATH="$close_log"
  bundle exec bin/roded --frontend qt "$close_path" >"$smoke_dir/close-$choice.out" 2>&1 &
  app_pid=$!
  for attempt in $(seq 1 100); do
    close_window_id=$(xdotool search --onlyvisible --name '^Roded$' 2>/dev/null | head -n 1 || true)
    if [[ -n "$close_window_id" ]]; then break; fi
    sleep 0.1
  done
  if [[ -z "$close_window_id" ]]; then
    cat "$smoke_dir/close-$choice.out"
    exit 1
  fi

  sleep 0.5
  xdotool windowfocus --sync "$close_window_id"
  xdotool mousemove --window "$close_window_id" 30 30 click 1
  xdotool type --clearmodifiers X
  xdotool key --clearmodifiers ctrl+x
  sleep 0.2
  xdotool key --clearmodifiers ctrl+c
  for attempt in $(seq 1 50); do
    if rg -q 'publish_ui_update: minibuffer_render' "$close_log"; then break; fi
    sleep 0.1
  done
  if ! rg -q 'publish_ui_update: minibuffer_render' "$close_log"; then
    printf 'Qt did not show the modified-buffer close prompt (%s)\n' "$choice" >&2
    exit 1
  fi
  xdotool type --clearmodifiers "$choice"
  xdotool key --clearmodifiers Return

  if [[ "$choice" == c ]]; then
    sleep 0.5
    app_state=$(ps -o stat= -p "$app_pid" || true)
    if [[ -z "$app_state" || "$app_state" == Z* ]]; then
      printf 'Qt app exited after close cancellation\n' >&2
      exit 1
    fi
    if [[ "$(cat "$close_path")" != "original" ]]; then
      printf 'Qt close cancellation changed the saved file\n' >&2
      exit 1
    fi
    xdotool windowfocus --sync "$close_window_id"
    xdotool mousemove --window "$close_window_id" 30 30 click 1
    xdotool key --clearmodifiers ctrl+slash
    sleep 0.3
    xdotool key --clearmodifiers ctrl+x
    sleep 0.2
    xdotool key --clearmodifiers ctrl+c
    wait_for_app_exit
  else
    wait_for_app_exit
  fi

  if [[ "$(cat "$close_path")" != "$expected_text" ]]; then
    printf 'Qt %s close produced unexpected file contents: %s\n' "$choice" "$(cat "$close_path")" >&2
    exit 1
  fi
}

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
xdotool windowfocus --sync "$window_id"
xdotool key --clearmodifiers ctrl+slash
sleep 0.3
xdotool key --clearmodifiers ctrl+x
sleep 0.3
xdotool key --clearmodifiers ctrl+s
saved_line=
for attempt in $(seq 1 50); do
  saved_line=$(sed -n '2p' "$smoke_dir/lines.txt")
  [[ "$saved_line" == "line 002" ]] && break
  sleep 0.1
done
if [[ "$saved_line" != "line 002" ]]; then
  printf 'Unexpected line after Qt undo: %s\n' "$saved_line" >&2
  exit 1
fi
sleep 0.5
import -window "$window_id" "$smoke_dir/after-undo.png"
xdotool windowfocus --sync "$window_id"
xdotool key --clearmodifiers ctrl+shift+slash
sleep 0.3
xdotool key --clearmodifiers ctrl+x
sleep 0.3
xdotool key --clearmodifiers ctrl+s
saved_line=
for attempt in $(seq 1 50); do
  saved_line=$(sed -n '2p' "$smoke_dir/lines.txt")
  [[ "$saved_line" == "Xline 002" ]] && break
  sleep 0.1
done
if [[ "$saved_line" != "Xline 002" ]]; then
  printf 'Unexpected line after Qt Ctrl+? redo: %s\n' "$saved_line" >&2
  exit 1
fi
sleep 0.5
import -window "$window_id" "$smoke_dir/after-redo.png"

# Keep the documented terminal-independent redo fallback covered as well.
xdotool windowfocus --sync "$window_id"
xdotool key --clearmodifiers ctrl+slash
sleep 0.3
xdotool key --clearmodifiers ctrl+x
sleep 0.3
xdotool key --clearmodifiers ctrl+s
saved_line=
for attempt in $(seq 1 50); do
  saved_line=$(sed -n '2p' "$smoke_dir/lines.txt")
  [[ "$saved_line" == "line 002" ]] && break
  sleep 0.1
done
if [[ "$saved_line" != "line 002" ]]; then
  printf 'Unexpected line after Qt undo before fallback redo: %s\n' "$saved_line" >&2
  exit 1
fi
xdotool windowfocus --sync "$window_id"
xdotool key --clearmodifiers ctrl+c
sleep 0.2
xdotool key --clearmodifiers r
xdotool key --clearmodifiers d
sleep 0.3
xdotool key --clearmodifiers ctrl+x
sleep 0.3
xdotool key --clearmodifiers ctrl+s
saved_line=
for attempt in $(seq 1 50); do
  saved_line=$(sed -n '2p' "$smoke_dir/lines.txt")
  [[ "$saved_line" == "Xline 002" ]] && break
  sleep 0.1
done
if [[ "$saved_line" != "Xline 002" ]]; then
  printf 'Unexpected line after Qt C-c r d redo: %s\n' "$saved_line" >&2
  exit 1
fi
sleep 0.5
import -window "$window_id" "$smoke_dir/after-edit-save.png"
xdotool windowfocus --sync "$window_id"
xdotool mousemove --window "$window_id" 30 40 click 1
sleep 0.5
import -window "$window_id" "$smoke_dir/after-blank-line-caret.png"
xdotool windowfocus --sync "$window_id"
xdotool mousemove --window "$window_id" 30 90 mousedown 1
xdotool mousemove --sync --window "$window_id" 90 90
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
xdotool type --clearmodifiers x
sleep 0.3
xdotool key --clearmodifiers ctrl+slash
sleep 0.3
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
  ! rg -q 'event received: key \{key: "x"' "$smoke_dir/scratch.log" ||
  ! rg -q 'event received: key \{key: "C-_"' "$smoke_dir/scratch.log" ||
  ! rg -q 'event received: key \{key: "C-c"' "$smoke_dir/scratch.log"; then
  printf 'Qt no-argument startup did not route keyboard input before any editor click\n' >&2
  exit 1
fi

run_close_prompt_smoke s $'original\nX'
run_close_prompt_smoke d "original"
run_close_prompt_smoke c "original"

RODED_LOG_PATH="$smoke_dir/roded.log"
printf 'Qt live smoke screenshots and log: %s\n' "$smoke_dir"
printf 'Empty scratch startup, typing, undo and quit before any editor click: passed\n'
printf 'Modified-buffer close: save, discard and cancel passed\n'
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
  [[ $(rg -c 'publish_ui_update: picker_render' "$RODED_LOG_PATH") -lt 2 ]]; then
  printf 'Qt Menu/Alt+Menu did not open both core pickers\n' >&2
  exit 1
fi
printf 'Menu shortcuts: project_files, switch_buffer\n'
if ! rg -q 'event received: key \{key: "C-_"' "$RODED_LOG_PATH" ||
  ! rg -Fq 'event received: key {key: "C-?"' "$RODED_LOG_PATH" ||
  ! rg -q 'event received: key \{key: "C-c"' "$RODED_LOG_PATH" ||
  ! rg -q 'event received: key \{key: "r"' "$RODED_LOG_PATH" ||
  ! rg -q 'event received: key \{key: "d"' "$RODED_LOG_PATH"; then
  printf 'Qt undo/redo shortcuts did not reach the core\n' >&2
  exit 1
fi
printf 'Undo/redo shortcuts: Ctrl+Slash, Ctrl+Shift+Slash, C-c r d\n'
