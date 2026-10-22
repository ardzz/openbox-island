# tests/tab/resolve.bats
load ../helpers
load common

@test "resolve picks the first tab in order when nothing is saved" {
  both
  run "$SCRIPTS/tab" resolve
  [ "$status" -eq 0 ]
  [ "$output" = musik ]
  [ "$(calls)" = "" ]
}

@test "resolve reopens the saved tab while it is available" {
  both; saved cuaca
  run "$SCRIPTS/tab" resolve
  [ "$output" = cuaca ]
}

@test "resolve treats paused music as available" {
  music paused; weather; saved musik
  run "$SCRIPTS/tab" resolve
  [ "$output" = musik ]
}

@test "resolve keeps music while the next track loads" {
  music loading; weather; saved musik
  run "$SCRIPTS/tab" resolve
  [ "$output" = musik ]
}

@test "resolve falls back to weather when the music stopped, keeping the saved choice" {
  no_music; weather; saved musik
  run "$SCRIPTS/tab" resolve
  [ "$output" = cuaca ]
  [ "$(cat "$ST/tab")" = musik ]
}

@test "resolve shows music when weather is unavailable" {
  music; no_weather; saved cuaca
  run "$SCRIPTS/tab" resolve
  [ "$output" = musik ]
}

@test "resolve treats a missing media state as no music" {
  weather; saved musik
  run "$SCRIPTS/tab" resolve
  [ "$output" = cuaca ]
}

@test "resolve ignores an unknown saved tab" {
  both; saved kalender
  run "$SCRIPTS/tab" resolve
  [ "$output" = musik ]
}

@test "resolve prefers an explicitly requested available tab without saving it" {
  both; saved cuaca
  run "$SCRIPTS/tab" resolve musik
  [ "$output" = musik ]
  [ "$(cat "$ST/tab")" = cuaca ]
  [ "$(calls)" = "" ]
}

@test "resolve skips a requested tab that is unavailable" {
  no_music; weather; saved musik
  run "$SCRIPTS/tab" resolve musik
  [ "$output" = cuaca ]
}

@test "resolve answers the first tab when nothing is available" {
  no_music; no_weather
  run "$SCRIPTS/tab" resolve
  [ "$status" -eq 0 ]
  [ "$output" = musik ]
}
