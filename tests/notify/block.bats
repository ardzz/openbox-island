load ../helpers
load common
bats_require_minimum_version 1.5.0

@test "an alert pauses the hold and the remaining hold resumes after it clears" {
  start_listener
  post 20 A
  next_event
  sleep 0.15
  signal '@alert 1'
  quiet 0.4
  signal '@alert 0'
  quiet 0.08
  next_event
  [ "$event" = "$CLEAR" ]
}

@test "a notification arriving during an alert waits until the alert clears" {
  start_listener
  signal '@alert 1'
  post 21 Antre
  quiet 0.2
  signal '@alert 0'
  next_event
  [ "$(jq -r .id <<< "$event")" = 21 ]
}

@test "an expanded island defers notifications and pauses the shown one" {
  start_listener
  signal '@expanded 1'
  post 22 Nanti
  quiet 0.2
  signal '@expanded 0'
  next_event
  [ "$(jq -r .id <<< "$event")" = 22 ]
  sleep 0.1
  signal '@expanded 1'
  quiet 0.4
  signal '@expanded 0'
  quiet 0.08
  next_event
  [ "$event" = "$CLEAR" ]
}

@test "a notification waits until both the alert and the expanded island are gone" {
  start_listener
  signal '@alert 1'
  signal '@expanded 1'
  post 23 Tunggu
  signal '@alert 0'
  quiet 0.15
  signal '@expanded 0'
  next_event
  [ "$(jq -r .id <<< "$event")" = 23 ]
}
