# tests/island/auto_close.bats
load ../helpers
load common

@test "auto expands, then collapses at its deadline when not hovered" {
  run "$SCRIPTS/island" auto 0
  [ "$status" -eq 0 ]
  wait_for_calls "$OPEN"$'\n'"$CLOSE"
  [ "$(calls)" = "$OPEN"$'\n'"$CLOSE" ]
}

@test "auto never collapses an island the pointer is on" {
  on_compact
  run "$SCRIPTS/island" auto 0
  [ "$(calls)" = "$OPEN" ]
}

@test "auto preserves the marquee start when already expanded" {
  expanded; on_compact
  mkdir -p "$ST"; echo 123 > "$ST/marquee_at"
  run "$SCRIPTS/island" auto 0
  [ "$status" -eq 0 ]
  [ "$(cat "$ST/marquee_at")" = 123 ]
  [ "$(calls)" = 'update island_tab=musik island_reveal=true' ]
}

@test "auto accepts durations with leading zeros" {
  run timeout 1 "$SCRIPTS/island" auto 08
  [ "$status" -eq 0 ]
  [ "$(calls)" = "$OPEN" ]
}

@test "close collapses an open island the pointer is not on" {
  expanded
  run "$SCRIPTS/island" close
  [ "$(calls)" = "$CLOSE" ]
}

@test "close that really collapses drops a pending picker request" {
  mkdir -p "$ST"; echo 1 > "$ST/todo-pick"
  expanded
  run "$SCRIPTS/island" close
  [ "$(calls)" = "$CLOSE" ]
  [ ! -e "$ST/todo-pick" ]
}

@test "close that keeps the card open for the pointer keeps the picker request" {
  mkdir -p "$ST"; echo 1 > "$ST/todo-pick"
  expanded; on_expanded_only
  run "$SCRIPTS/island" close
  [ "$status" -eq 0 ]
  [ "$(calls)" = 'update island_tab=musik' ]
  [ -e "$ST/todo-pick" ]
}

@test "close keeps an island the pointer is on open (player gone while hovering)" {
  expanded; on_expanded_only
  run "$SCRIPTS/island" close
  [ "$status" -eq 0 ]
  [ "$(calls)" = 'update island_tab=musik' ]
}

@test "close cancels a running auto-expand" {
  expanded; auto_running
  run "$SCRIPTS/island" close
  [ "$(calls)" = "$CLOSE" ]
  [ "$(cat "$ST/auto_until")" = 0 ]
}

@test "close on a collapsed island touches nothing" {
  run "$SCRIPTS/island" close
  [ "$status" -eq 0 ]
  [ "$(calls)" = "" ]
}

@test "unknown commands and bad durations are rejected without touching eww" {
  run "$SCRIPTS/island" auto soon; [ "$status" -eq 2 ]
  run "$SCRIPTS/island" explode;   [ "$status" -eq 2 ]
  run "$SCRIPTS/island" hover-on;  [ "$status" -eq 2 ]
  [ "$(calls)" = "" ]
}
