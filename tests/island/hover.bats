# tests/island/hover.bats
load ../helpers
load common

@test "hover waits 0.3 seconds without a lock and opens when the pointer stays on the island" {
  stub_hover_sleep; on_compact
  run "$SCRIPTS/island" hover
  [ "$status" -eq 0 ]
  [ "$(calls)" = "$OPEN" ]
  [[ $(cat "$ST/marquee_at") =~ ^[0-9]+$ ]]
  [ "$(cat "$FAKE_SLEEP_LOG")" = 0.3 ]
}

@test "hover never opens when the pointer leaves the island during the 0.3 second delay" {
  stub_hover_sleep; on_compact
  export FAKE_POINTER_AFTER_HOVER_DELAY='960 700'
  run "$SCRIPTS/island" hover
  [ "$status" -eq 0 ]
  [ "$(calls)" = "" ]
  [ "$(cat "$FAKE_SLEEP_LOG")" = 0.3 ]
  [ ! -e "$ST/marquee_at" ]
}

@test "hover over an open island only reveals it without waiting" {
  stub_hover_sleep; expanded; on_expanded_only
  mkdir -p "$ST"; echo 123 > "$ST/marquee_at"
  run "$SCRIPTS/island" hover
  [ "$status" -eq 0 ]
  [ "$(calls)" = 'update island_reveal=true' ]
  [ "$(cat "$ST/marquee_at")" = 123 ]
  [ ! -s "$FAKE_SLEEP_LOG" ]
}

@test "hover after the pointer left hides, then closes the expanded window" {
  expanded
  run "$SCRIPTS/island" hover
  [ "$status" -eq 0 ]
  [ "$(calls)" = "$CLOSE" ]
}

@test "a crossing event while the pointer stays on the island (pointer grab) never collapses it" {
  expanded; on_compact
  run "$SCRIPTS/island" hover
  [ "$status" -eq 0 ]
  [ "$(calls)" = 'update island_reveal=true' ]
}

@test "a stale hover for a pointer that already left never opens the island" {
  run "$SCRIPTS/island" hover
  [ "$status" -eq 0 ]
  [ "$(calls)" = "" ]
}

@test "a pointer that left while the window opened collapses it again" {
  on_compact; export FAKE_POINTER_AFTER_OPEN='960 700'
  run "$SCRIPTS/island" hover
  [ "$(calls)" = "$OPEN"$'\n'"$CLOSE" ]
}

@test "hover away keeps the island open until a running auto-expand ends" {
  expanded; auto_running
  run "$SCRIPTS/island" hover
  [ "$status" -eq 0 ]
  [ "$(calls)" = "" ]
}

@test "a pointer that comes back while the island is hiding keeps it open" {
  expanded
  "$SCRIPTS/island" hover & pid=$!
  for _ in {1..40}; do grep -qx 'update island_reveal=false' "$FAKE_EWW_LOG" && break; sleep 0.05; done
  on_expanded_only
  wait "$pid"
  [ "$(calls)" = $'update island_reveal=false\nupdate island_reveal=true' ]
}

@test "concurrent hover calls open the expanded window once" {
  on_compact; export FAKE_EWW_OPEN_DELAY=0.2
  "$SCRIPTS/island" hover & "$SCRIPTS/island" hover & wait
  [ "$(grep -c '^open island-expanded$' "$FAKE_EWW_LOG")" = 1 ]
}
