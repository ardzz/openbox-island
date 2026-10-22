# tests/status/main.bats
load ../helpers
load common

@test "status is executable and unavailable sources produce one complete initial snapshot" {
  rm "$BIN/pactl" "$BIN/inotifywait" "$BIN/dunstctl" "$BIN/dbus-monitor" "$BIN/gdbus" "$BIN/bluetoothctl"
  [ -x "$SCRIPTS/status" ]
  start_listener
  [ "$first" = "$EMPTY" ]
  assert_silent
}

@test "missing dunstctl skips its monitor without disabling other sources" {
  rm "$BIN/dunstctl"
  start_listener
  [ "$first" = "$EMPTY" ]
  wait_ready audio
  assert_silent
  [ ! -e "$STATUS_FIXTURE/dnd-ready" ]
  printf '[{"source":66,"properties":{"application.name":"Zoom"}}]\n' > "$STATUS_FIXTURE/outputs"
  printf "Event 'new' on source-output #1\n" >&"$audio_fd"
  next_event
  [ "$(jq -c '[.mic,.dnd]' <<< "$event")" = '[true,false]' ]
}

@test "stream emits initial JSON then one full changed snapshot and suppresses unchanged queries" {
  start_listener
  [ "$first" = "$EMPTY" ]
  wait_ready dnd
  printf 'true\n' > "$STATUS_FIXTURE/paused"
  printf 'signal member=PropertiesChanged\n' >&"$dnd_fd"
  next_event
  [ "$event" = '{"mic":false,"mic_apps":"","camera":false,"camera_apps":"","dnd":true,'"$HP_NONE"'}' ]
  printf 'signal member=PropertiesChanged\n' >&"$dnd_fd"
  assert_silent
  [ "$(cat "$STATUS_FIXTURE/dunst-calls")" = $'query\nquery\nquery' ]
}
