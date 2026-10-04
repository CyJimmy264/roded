#!/usr/bin/env bash
set -euo pipefail
if [[ $# -eq 0 || "$1" != "--inside-xvfb" ]]; then
  exec xvfb-run -a -s "-screen 0 1280x800x24" "$0" --inside-xvfb
fi
smoke_dir=$(mktemp -d /tmp/roded-two-file-qt.XXXXXX)
repository=$(pwd)
export QT_QPA_PLATFORM=xcb
export XDG_CONFIG_HOME="$smoke_dir/config"
export XDG_CACHE_HOME="$smoke_dir/cache"
export RODED_LOG_PATH="$smoke_dir/roded.log"
export RODED_LOG_LEVEL=DEBUG
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
ruby_path="$smoke_dir/editor.rb"
text_path="$smoke_dir/notes.txt"
ruby_copy="$smoke_dir/editor-copy.rb"
text_copy="$smoke_dir/notes-copy.txt"
expected_path="$smoke_dir/expected"
printf 'puts "cat"\n' > "$ruby_path"
printf 'cat dog cat\n' > "$text_path"

press() { xdotool key --clearmodifiers "$1"; sleep 0.25; }
type_text() { xdotool type --clearmodifiers --delay 1 "$1"; }
assert_file() {
  local path=$1 expected=$2
  printf '%s' "$expected" > "$expected_path"
  for attempt in $(seq 1 80); do
    if cmp -s "$path" "$expected_path"; then return; fi
    sleep 0.1
  done
  printf 'Unexpected contents in %s\n' "$path" >&2
  od -An -tc "$path" >&2
  exit 1
}
log_count() {
  local count
  count=$(rg -F -c "$1" "$RODED_LOG_PATH" || true)
  [[ "$count" =~ ^[0-9]+$ ]] || count=0
  printf '%s' "$count"
}
wait_for_log_count() {
  local label=$1 target=$2 current
  for attempt in $(seq 1 120); do
    current=$(log_count "$label")
    if (( current >= target )); then return; fi
    sleep 0.1
  done
  printf 'Timed out waiting for %s count %s (last %s)\n' "$label" "$target" "$current" >&2
  exit 1
}
type_minibuffer_text() {
  local value=$1 renders length
  renders=$(log_count 'publish_ui_update: minibuffer_render')
  length=$(printf '%s' "$value" | wc -c)
  type_text "$value"
  wait_for_log_count 'publish_ui_update: minibuffer_render' "$((renders + length))"
}
query_replace_all() {
  local query=$1 replacement=$2
  local clear_count render_count
  clear_count=$(log_count 'publish_ui_update: minibuffer_clear')
  render_count=$(log_count 'publish_ui_update: minibuffer_render')
  press alt+shift+comma
  press alt+shift+5
  wait_for_log_count 'publish_ui_update: minibuffer_render' "$((render_count + 1))"
  type_minibuffer_text "$query"
  press Return
  wait_for_log_count 'publish_ui_update: minibuffer_clear' "$((clear_count + 1))"
  type_minibuffer_text "$replacement"
  press Return
  wait_for_log_count 'publish_ui_update: minibuffer_clear' "$((clear_count + 2))"
  type_minibuffer_text '!'
  press Return
  wait_for_log_count 'publish_ui_update: minibuffer_clear' "$((clear_count + 3))"
}
save_as() {
  local path=$1 expected=$2 renders clears
  renders=$(log_count 'publish_ui_update: minibuffer_render')
  clears=$(log_count 'publish_ui_update: minibuffer_clear')
  press ctrl+x
  press ctrl+w
  wait_for_log_count 'publish_ui_update: minibuffer_render' "$((renders + 1))"
  type_minibuffer_text "$(basename "$path")"
  press Return
  wait_for_log_count 'publish_ui_update: minibuffer_clear' "$((clears + 1))"
  assert_file "$path" "$expected"
}
cd "$smoke_dir"
export BUNDLE_GEMFILE="$repository/Gemfile"
export RBENV_DIR="$repository"
bundle exec "$repository/bin/roded" --frontend qt "$ruby_path" "$text_path" >"$smoke_dir/app.out" 2>&1 &
app_pid=$!
cleanup() {
  if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then
    kill "$app_pid" 2>/dev/null || true
    wait "$app_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT
window_id=
for attempt in $(seq 1 100); do
  window_id=$(xdotool search --onlyvisible --name '^Roded$' 2>/dev/null | head -n 1 || true)
  [[ -n "$window_id" ]] && break
  sleep 0.1
done
[[ -n "$window_id" ]] || { cat "$smoke_dir/app.out"; exit 1; }
sleep 1
xdotool windowfocus --sync "$window_id"
xdotool mousemove --window "$window_id" 120 100 click 1
sleep 0.3

# The second CLI file is active initially. Edit/save it, then switch to Ruby.
press alt+shift+comma
type_text X
press ctrl+x
press ctrl+s
assert_file "$text_path" $'Xcat dog cat\n'
press ctrl+x
press Left
press alt+shift+comma
type_text Y
press ctrl+x
press ctrl+s
assert_file "$ruby_path" $'Yputs "cat"\n'

# Split the Ruby document, maintain distinct view points, and share its edits.
press ctrl+x
press 3
sleep 0.5
press ctrl+e
press ctrl+x
press o
type_text Z
sleep 0.4
press ctrl+x
press ctrl+s
assert_file "$ruby_path" $'YZputs "cat"\n'
sleep 0.5
import -window "$window_id" "$smoke_dir/shared-view.png"
press ctrl+x
press o
type_text W
press ctrl+x
press ctrl+s
assert_file "$ruby_path" $'YZputs "cat"W\n'

# Replace every cat in Ruby, save, and save-as to a new file.
query_replace_all cat fox
press ctrl+x
press ctrl+s
sleep 0.5
assert_file "$ruby_path" $'YZputs "fox"W\n'
sleep 0.5
import -window "$window_id" "$smoke_dir/query-replace-save.png"
save_as "$ruby_copy" $'YZputs "fox"W\n'

# Switch to the second document and exercise line query-replace and save-as.
press ctrl+x
press Right
query_replace_all cat fox
press ctrl+x
press ctrl+s
assert_file "$text_path" $'Xfox dog fox\n'
save_as "$text_copy" $'Xfox dog fox\n'

# Kill and reopen the saved-as document, then exit with clean buffers.
press ctrl+x
press k
sleep 2
import -window "$window_id" "$smoke_dir/after-kill.png"
renders=$(log_count 'publish_ui_update: minibuffer_render')
press ctrl+x
press ctrl+f
wait_for_log_count 'publish_ui_update: minibuffer_render' "$((renders + 1))"
type_minibuffer_text "$(basename "$text_copy")"
clears=$(log_count 'publish_ui_update: minibuffer_clear')
renders=$(log_count 'publish_ui_update: render')
press Return
wait_for_log_count 'publish_ui_update: minibuffer_clear' "$((clears + 1))"
wait_for_log_count 'publish_ui_update: render' "$((renders + 1))"
sleep 2
import -window "$window_id" "$smoke_dir/reopened-text.png"

# Search the reopened buffer through Qt's live line picker.
renders=$(log_count 'publish_ui_update: minibuffer_render')
clears=$(log_count 'publish_ui_update: minibuffer_clear')
press ctrl+s
wait_for_log_count 'publish_ui_update: minibuffer_render' "$((renders + 1))"
type_minibuffer_text dog
press Return
wait_for_log_count 'publish_ui_update: minibuffer_clear' "$((clears + 1))"
press alt+shift+comma

# Exercise a real region cut/yank and verify undo/redo from the visible Qt view.
press ctrl+space
press ctrl+f
press ctrl+w
press ctrl+x
press ctrl+s
assert_file "$text_copy" $'fox dog fox\n'
press ctrl+y
press ctrl+x
press ctrl+s
assert_file "$text_copy" $'Xfox dog fox\n'
press ctrl+slash
press ctrl+x
press ctrl+s
assert_file "$text_copy" $'fox dog fox\n'
press ctrl+shift+slash
press ctrl+x
press ctrl+s
assert_file "$text_copy" $'Xfox dog fox\n'

press ctrl+x
press ctrl+c
for attempt in $(seq 1 50); do
  state=$(ps -o stat= -p "$app_pid" 2>/dev/null || true)
  [[ -z "$state" || "$state" == Z* ]] && break
  sleep 0.1
done
if [[ -n "$state" && "$state" != Z* ]]; then
  echo "Qt did not exit after full acceptance scenario" >&2
  exit 1
fi
wait "$app_pid"
app_pid=
[[ "$(cat "$ruby_path")" == 'YZputs "fox"W' ]]
[[ "$(cat "$text_path")" == 'Xfox dog fox' ]]
[[ "$(cat "$ruby_copy")" == 'YZputs "fox"W' ]]
[[ "$(cat "$text_copy")" == 'Xfox dog fox' ]]
printf 'Qt two-file acceptance passed; artifacts=%s\n' "$smoke_dir"
