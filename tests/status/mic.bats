# tests/status/mic.bats
load ../helpers
load common

@test "monitor-source, viz-tagged and capture-sink outputs do not light the microphone" {
  cat > "$STATUS_FIXTURE/outputs" <<'EOF'
[{"index":1,"source":67,"client":"10973","properties":{"application.name":"Monitor","application.process.binary":null}},
 {"index":2,"source":66,"properties":{"application.name":"eww-island-viz"}},
 {"index":3,"source":66,"properties":{"application.name":"Recorder","stream.capture.sink":"true"}}]
EOF
  start_listener
  [ "$first" = "$EMPTY" ]
  assert_silent
}

@test "microphone app names are unique sorted and use binary then Indonesian fallbacks" {
  cat > "$STATUS_FIXTURE/outputs" <<'EOF'
[{"index":10974,"source":66,"client":"10973","properties":{"application.name":"Zoom","application.process.binary":null,"media.class":"Stream/Input/Audio"}},
 {"index":2,"source":66,"properties":{"application.name":"Alpha","application.process.binary":"ignored"}},
 {"index":3,"source":66,"properties":{"application.name":"Zoom"}},
 {"index":4,"source":66,"properties":{"application.name":null,"application.process.binary":"recorder"}},
 {"index":5,"source":66,"properties":{}},
 {"index":6,"source":66,"properties":{"application.name":"","application.process.binary":""}}]
EOF
  start_listener
  [ "$first" = '{"mic":true,"mic_apps":"Alpha, Aplikasi, Zoom, recorder","camera":false,"camera_apps":"","dnd":false,'"$HP_NONE"'}' ]
}

@test "audio noise does not query the microphone while source-output source and server events refresh it" {
  start_listener
  [ "$first" = "$EMPTY" ]
  wait_ready audio
  printf '[{"source":66,"properties":{"application.name":"Zoom"}}]\n' > "$STATUS_FIXTURE/outputs"
  printf "%s\n" "Event 'new' on client #9" "Event 'change' on card #2" \
    "Event 'change' on sink-input #3" "Event 'change' on sink #4" >&"$audio_fd"
  assert_silent
  [ "$(count_calls pactl-calls '-f json list source-outputs')" -eq 1 ]
  printf "Event 'new' on source-output #10974\n" >&"$audio_fd"
  next_event
  [ "$(jq -c '[.mic,.mic_apps]' <<< "$event")" = '[true,"Zoom"]' ]
  printf '[{"index":66,"name":"new.monitor"}]\n' > "$STATUS_FIXTURE/sources"
  printf "Event 'change' on source #66\n" >&"$audio_fd"
  next_event
  [ "$event" = "$EMPTY" ]
  printf '[{"index":66,"name":"microphone"}]\n' > "$STATUS_FIXTURE/sources"
  printf "Event 'change' on server\n" >&"$audio_fd"
  next_event
  [ "$(jq -c '[.mic,.mic_apps]' <<< "$event")" = '[true,"Zoom"]' ]
}

assert_bad_mic_does_not_block() {
  printf '[{"source":66,"properties":{"application.name":"Zoom"}}]\n' > "$STATUS_FIXTURE/outputs"
  printf '%s' "$2" > "$STATUS_FIXTURE/$1"
  start_listener
  [ "$first" = "$EMPTY" ]
  wait_ready dnd
  printf 'true\n' > "$STATUS_FIXTURE/paused"
  printf 'signal member=PropertiesChanged\n' >&"$dnd_fd"
  next_event
  [ "$event" = '{"mic":false,"mic_apps":"","camera":false,"camera_apps":"","dnd":true,'"$HP_NONE"'}' ]
}

@test "empty microphone output does not block initial or DND snapshots" {
  assert_bad_mic_does_not_block outputs ''
}

@test "non-JSON microphone output does not block initial or DND snapshots" {
  assert_bad_mic_does_not_block outputs 'not JSON'
}

@test "empty source list does not block initial or DND snapshots" {
  assert_bad_mic_does_not_block sources ''
}

@test "non-JSON source list does not block initial or DND snapshots" {
  assert_bad_mic_does_not_block sources 'not JSON'
}

@test "microphone refreshes after reconnect without needing a replacement event" {
  printf '[{"source":66,"properties":{"application.name":"Zoom"}}]\n' > "$STATUS_FIXTURE/outputs"
  start_listener
  [ "$(jq -c '[.mic,.mic_apps]' <<< "$first")" = '[true,"Zoom"]' ]
  wait_ready audio
  local monitor
  IFS= read -r monitor < "$STATUS_FIXTURE/audio-ready"
  kill -TERM "$monitor"
  printf '[]\n' > "$STATUS_FIXTURE/outputs"
  next_event
  [ "$event" = "$EMPTY" ]
  assert_silent
}
