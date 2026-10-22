# tests/status/camera.bats
load ../helpers
load common

@test "camera scans fake proc descriptors and joins unique trimmed comm names" {
  : > "$ISLAND_DEV/video0"
  : > "$ISLAND_DEV/video1"
  mkdir -p "$ISLAND_PROC/111/fd" "$ISLAND_PROC/222/fd" "$ISLAND_PROC/333/fd"
  printf '  Zoom  \n' > "$ISLAND_PROC/111/comm"
  printf 'Browser\n' > "$ISLAND_PROC/222/comm"
  printf 'Zoom\n' > "$ISLAND_PROC/333/comm"
  "$STATUS_LINK" -s "$ISLAND_DEV/video0" "$ISLAND_PROC/111/fd/3"
  "$STATUS_LINK" -s "$ISLAND_DEV/video1" "$ISLAND_PROC/222/fd/4"
  "$STATUS_LINK" -s "$ISLAND_DEV/video0" "$ISLAND_PROC/333/fd/5"
  start_listener
  [ "$first" = '{"mic":false,"mic_apps":"","camera":true,"camera_apps":"Browser, Zoom","dnd":false,'"$HP_NONE"'}' ]
  wait_ready camera
  rm "$ISLAND_PROC/111/fd/3" "$ISLAND_PROC/222/fd/4" "$ISLAND_PROC/333/fd/5"
  printf '%s CLOSE\n' "$ISLAND_DEV/video0" >&"$camera_fd"
  next_event
  [ "$event" = "$EMPTY" ]
  "$STATUS_LINK" -s "$ISLAND_DEV/video1" "$ISLAND_PROC/222/fd/6"
  printf '%s OPEN\n' "$ISLAND_DEV/video1" >&"$camera_fd"
  next_event
  [ "$(jq -c '[.camera,.camera_apps]' <<< "$event")" = '[true,"Browser"]' ]
}

@test "camera excludes the listener own PID" {
  : > "$ISLAND_DEV/video0"
  include_own_fd=1
  start_listener
  [ "$first" = "$EMPTY" ]
  wait_ready camera
  printf '%s OPEN\n' "$ISLAND_DEV/video0" >&"$camera_fd"
  assert_silent
}

@test "no video devices leaves camera false without launching inotifywait" {
  start_listener
  [ "$first" = "$EMPTY" ]
  wait_ready dnd
  assert_silent
  [ ! -e "$STATUS_FIXTURE/inotify-calls" ]
}

@test "camera refreshes after reconnect without needing a replacement event" {
  : > "$ISLAND_DEV/video0"
  mkdir -p "$ISLAND_PROC/111/fd"
  printf 'Zoom\n' > "$ISLAND_PROC/111/comm"
  "$STATUS_LINK" -s "$ISLAND_DEV/video0" "$ISLAND_PROC/111/fd/3"
  start_listener
  [ "$(jq -c '[.camera,.camera_apps]' <<< "$first")" = '[true,"Zoom"]' ]
  wait_ready camera
  local monitor
  IFS= read -r monitor < "$STATUS_FIXTURE/camera-ready"
  kill -TERM "$monitor"
  rm "$ISLAND_PROC/111/fd/3"
  next_event
  [ "$event" = "$EMPTY" ]
  assert_silent
}
