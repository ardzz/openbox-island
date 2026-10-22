# tests/island/signals.bats
load ../helpers
load common

@test "expanding and collapsing tell the notification listener" {
  mkdir -p "$ST"; mkfifo "$ST/notify.fifo"
  exec {notify_fd}<> "$ST/notify.fifo"
  stub_hover_sleep; on_compact
  run "$SCRIPTS/island" hover
  [ "$(calls)" = "$OPEN" ]
  IFS= read -r -t 1 -u "$notify_fd" signal
  [ "$signal" = '@expanded 1' ]
  away; : > "$FAKE_EWW_LOG"
  run "$SCRIPTS/island" hover
  [ "$(calls)" = "$CLOSE" ]
  IFS= read -r -t 1 -u "$notify_fd" signal
  [ "$signal" = '@expanded 0' ]
  if IFS= read -r -t 0.1 -u "$notify_fd" signal; then false; fi
}

@test "expanding and collapsing tell the notification center" {
  mkdir -p "$ST"; mkfifo "$ST/notif.fifo"
  exec {notif_fd}<> "$ST/notif.fifo"
  stub_hover_sleep; on_compact
  run "$SCRIPTS/island" hover
  IFS= read -r -t 1 -u "$notif_fd" signal
  [ "$signal" = '@expanded 1' ]
  away
  run "$SCRIPTS/island" hover
  IFS= read -r -t 1 -u "$notif_fd" signal
  [ "$signal" = '@expanded 0' ]
}

@test "collapsing tells the to-do list to scroll back to the top" {
  mkdir -p "$ST"; mkfifo "$ST/todo.fifo"
  exec {todo_fd}<> "$ST/todo.fifo"
  expanded
  run "$SCRIPTS/island" hover
  [ "$(calls)" = "$CLOSE" ]
  IFS= read -r -t 1 -u "$todo_fd" signal
  [ "$signal" = '@expanded 0' ]
}

@test "a pointer that comes back while hiding never reports a collapse" {
  mkdir -p "$ST"; mkfifo "$ST/notify.fifo"
  exec {notify_fd}<> "$ST/notify.fifo"
  expanded
  "$SCRIPTS/island" hover & pid=$!
  for _ in {1..40}; do grep -qx 'update island_reveal=false' "$FAKE_EWW_LOG" && break; sleep 0.05; done
  on_expanded_only
  wait "$pid"
  [ "$(calls)" = $'update island_reveal=false\nupdate island_reveal=true' ]
  if IFS= read -r -t 0.2 -u "$notify_fd" signal; then false; fi
}
