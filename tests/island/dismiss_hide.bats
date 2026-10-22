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
