# tests/status/dnd.bats
load ../helpers
load common

@test "initial dunst paused state is true only for literal true" {
  printf 'true\n' > "$STATUS_FIXTURE/paused"
  start_listener
  [ "$first" = '{"mic":false,"mic_apps":"","camera":false,"camera_apps":"","dnd":true,'"$HP_NONE"'}' ]
  wait_ready dnd
  printf 'false\n' > "$STATUS_FIXTURE/paused"
  printf 'signal member=NameOwnerChanged\n' >&"$dnd_fd"
  next_event
  [ "$event" = "$EMPTY" ]
  printf 'unexpected\n' > "$STATUS_FIXTURE/paused"
  printf 'signal member=PropertiesChanged\n' >&"$dnd_fd"
  assert_silent
}

@test "DND refreshes after reconnect without needing a replacement event" {
  printf 'true\n' > "$STATUS_FIXTURE/paused"
  start_listener
  [ "$(jq -r '.dnd' <<< "$first")" = true ]
  wait_ready dnd
  local monitor
  IFS= read -r monitor < "$STATUS_FIXTURE/dnd-ready"
  kill -TERM "$monitor"
  printf 'false\n' > "$STATUS_FIXTURE/paused"
  next_event
  [ "$event" = "$EMPTY" ]
  assert_silent
}
