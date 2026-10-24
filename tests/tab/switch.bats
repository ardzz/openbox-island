# tests/tab/switch.bats
load ../helpers
load common

@test "select saves the tab and shows it" {
  both; shown musik
  run "$SCRIPTS/tab" select cuaca
  [ "$status" -eq 0 ]
  [ "$(cat "$ST/tab")" = cuaca ]
  [ "$(calls)" = 'update island_tab=cuaca' ]
}

@test "select rejects an unknown tab without touching eww or the saved choice" {
  both; saved musik
  run "$SCRIPTS/tab" select rahasia
  [ "$status" -eq 2 ]
  [ "$(cat "$ST/tab")" = musik ]
  [ "$(calls)" = "" ]
}

@test "next moves to the following available tab and saves it" {
  both; shown musik
  run "$SCRIPTS/tab" next
  [ "$status" -eq 0 ]
  [ "$(calls)" = 'update island_tab=cuaca' ]
  [ "$(cat "$ST/tab")" = cuaca ]
}

@test "next wraps from the last available tab to the first" {
  both; shown cuaca
  run "$SCRIPTS/tab" next
  [ "$(calls)" = 'update island_tab=musik' ]
  [ "$(cat "$ST/tab")" = musik ]
}

@test "prev wraps from the first available tab to the last" {
  both; shown musik
  run "$SCRIPTS/tab" prev
  [ "$(calls)" = 'update island_tab=cuaca' ]
}

@test "scroll down and up on the header map to next and prev" {
  both; shown musik
  run "$SCRIPTS/tab" down
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_TAB")" = cuaca ]
  rm -f "$ST/tab_at"
  run "$SCRIPTS/tab" up
  [ "$(cat "$FAKE_TAB")" = musik ]
}

@test "next with a single available tab changes nothing" {
  no_music; weather; shown cuaca; saved musik
  run "$SCRIPTS/tab" next
  [ "$status" -eq 0 ]
  [ "$(calls)" = "" ]
  [ "$(cat "$ST/tab")" = musik ]
}

@test "a burst of scroll events switches the tab only once" {
  both; shown musik
  run "$SCRIPTS/tab" next
  run "$SCRIPTS/tab" next
  run "$SCRIPTS/tab" next
  [ "$(calls)" = 'update island_tab=cuaca' ]
}

@test "scrolling again after the burst settles switches again" {
  both; shown musik
  run "$SCRIPTS/tab" next
  echo 0 > "$ST/tab_at"
  run "$SCRIPTS/tab" next
  [ "$(calls)" = $'update island_tab=cuaca\nupdate island_tab=musik' ]
}

@test "clicking a tab is never swallowed by the scroll debounce" {
  both; shown musik
  run "$SCRIPTS/tab" next
  run "$SCRIPTS/tab" select musik
  [ "$(calls)" = $'update island_tab=cuaca\nupdate island_tab=musik' ]
}

@test "unknown commands are rejected" {
  run "$SCRIPTS/tab" explode
  [ "$status" -eq 2 ]
  run "$SCRIPTS/tab"
  [ "$status" -eq 2 ]
  [ "$(calls)" = "" ]
}
