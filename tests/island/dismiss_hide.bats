# tests/island/dismiss_hide.bats
load ../helpers
load common

@test "dismiss hides and closes the card even with the pointer on it" {
  expanded; on_expanded_only; auto_running
  run "$SCRIPTS/island" dismiss
  [ "$status" -eq 0 ]
  [ "$(calls)" = "$CLOSE" ]
  [ "$(cat "$ST/auto_until")" = 0 ]
}

@test "dismiss tells the notification listeners the pill is back" {
  mkdir -p "$ST"; mkfifo "$ST/notify.fifo" "$ST/notif.fifo"
  exec {notify_fd}<> "$ST/notify.fifo" {notif_fd}<> "$ST/notif.fifo"
  expanded; on_expanded_only
  run "$SCRIPTS/island" dismiss
  IFS= read -r -t 1 -u "$notify_fd" signal
  [ "$signal" = '@expanded 0' ]
  IFS= read -r -t 1 -u "$notif_fd" signal
  [ "$signal" = '@expanded 0' ]
}

@test "dismiss on a collapsed island touches nothing" {
  run "$SCRIPTS/island" dismiss
  [ "$status" -eq 0 ]
  [ "$(calls)" = "" ]
}

@test "dismiss and hide tell the to-do list to scroll back to the top" {
  mkdir -p "$ST"; mkfifo "$ST/todo.fifo"
  exec {todo_fd}<> "$ST/todo.fifo"
  expanded; on_expanded_only
  run "$SCRIPTS/island" dismiss
  IFS= read -r -t 1 -u "$todo_fd" signal
  [ "$signal" = '@expanded 0' ]
  expanded
  run "$SCRIPTS/island" hide
  IFS= read -r -t 1 -u "$todo_fd" signal
  [ "$signal" = '@expanded 0' ]
}

@test "dismiss drops a pending picker request before closing the card" {
  mkdir -p "$ST"; echo 1 > "$ST/todo-pick"
  expanded; on_expanded_only
  run "$SCRIPTS/island" dismiss
  [ "$status" -eq 0 ]
  [ "$(calls)" = "$CLOSE" ]
  [ ! -e "$ST/todo-pick" ]
}

@test "hide drops a pending picker request before closing the card" {
  mkdir -p "$ST"; echo 1 > "$ST/todo-pick"
  expanded; on_expanded_only
  run "$SCRIPTS/island" hide
  [ "$status" -eq 0 ]
  [ ! -e "$ST/todo-pick" ]
}

@test "a fresh todo listener after the card closed emits the picker closed, not the stale request" {
  mkdir -p "$ST" "$BATS_TEST_TMPDIR/data"
  export XDG_DATA_HOME="$BATS_TEST_TMPDIR/data"
  "$SCRIPTS/todo" add a
  echo 1 > "$ST/todo-pick"
  expanded; on_expanded_only
  run "$SCRIPTS/island" dismiss
  [ "$status" -eq 0 ]
  [ ! -e "$ST/todo-pick" ]
  # Ordinary reopen: a fresh card-only listener emits its first JSON.
  mkdir -p "$BATS_TEST_TMPDIR/run2"
  FIFO_OUT="$BATS_TEST_TMPDIR/todo-first.json"
  XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run" timeout 2 "$SCRIPTS/todo" > "$FIFO_OUT" 2>/dev/null &
  wait $! || true
  run jq -c .picker "$FIFO_OUT"
  [ "$status" -eq 0 ]
  [ "$output" = '{"show":false,"id":0,"text":"","month_label":"","weeks":[],"hour":"","minute":"","summary":""}' ]
}

@test "dismiss while a fullscreen window hides the island keeps it hidden" {
  mkdir -p "$ST"; : > "$ST/fullscreen"; : > "$FAKE_EWW_ACTIVE"
  run "$SCRIPTS/island" dismiss
  [ "$status" -eq 0 ]
  [ "$(calls)" = "" ]
  [ -e "$ST/fullscreen" ]
}

@test "hover and auto never open the card while a fullscreen window hides the island" {
  mkdir -p "$ST"; : > "$ST/fullscreen"
  stub_hover_sleep; on_compact
  run "$SCRIPTS/island" hover
  [ "$status" -eq 0 ]
  run "$SCRIPTS/island" auto 0
  [ "$status" -eq 0 ]
  sleep 0.2
  [ "$(calls)" = "" ]
}

@test "hide closes the left pill with the compact island and show opens both again" {
  run "$SCRIPTS/island" hide
  [ "$status" -eq 0 ]
  [ "$(grep -E '^(open|close)' "$FAKE_EWW_LOG")" = $'close island-upcoming\nclose island' ]
  : > "$FAKE_EWW_LOG"
  run "$SCRIPTS/island" show
  [ "$status" -eq 0 ]
  [ "$(grep -E '^(open|close)' "$FAKE_EWW_LOG")" = $'open island\nopen island-upcoming' ]
}

@test "show reports a compact island that fails to reopen but still opens the left pill" {
  run "$SCRIPTS/island" hide
  [ "$status" -eq 0 ]
  : > "$FAKE_EWW_LOG"
  FAKE_EWW_OPEN_FAIL=island run "$SCRIPTS/island" show
  [ "$status" -ne 0 ]
  [ "$(grep -E '^(open|close)' "$FAKE_EWW_LOG")" = 'open island-upcoming' ]
}
