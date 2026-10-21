load helpers

setup() {
  export STATUS_FIXTURE="$BATS_TEST_TMPDIR"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export ISLAND_DEV="$BATS_TEST_TMPDIR/dev"
  export ISLAND_PROC="$BATS_TEST_TMPDIR/proc"
  export STATUS_LINK
  STATUS_LINK=$(command -v ln)
  ORIGINAL_PATH=$PATH
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN" "$XDG_RUNTIME_DIR" "$ISLAND_DEV" "$ISLAND_PROC"
  local tool
  for tool in bash cat chmod date dirname find jq ln mkdir mkfifo mktemp readlink rm rmdir sleep sort touch tr uniq wc; do
    ln -s "$(command -v "$tool")" "$BIN/$tool"
  done
  printf '[]\n' > "$STATUS_FIXTURE/outputs"
  printf '[{"index":66,"name":"alsa_input.test"},{"index":67,"name":"alsa_output.test.monitor"}]\n' > "$STATUS_FIXTURE/sources"
  printf 'false\n' > "$STATUS_FIXTURE/paused"
  mkfifo "$STATUS_FIXTURE/audio-events" "$STATUS_FIXTURE/camera-events" \
    "$STATUS_FIXTURE/dnd-events" "$STATUS_FIXTURE/output"
  exec {audio_fd}<> "$STATUS_FIXTURE/audio-events"
  exec {camera_fd}<> "$STATUS_FIXTURE/camera-events"
  exec {dnd_fd}<> "$STATUS_FIXTURE/dnd-events"
  exec {output_fd}<> "$STATUS_FIXTURE/output"
  cat > "$BIN/pactl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STATUS_FIXTURE/pactl-calls"
case "$*" in
  '-f json list source-outputs') cat "$STATUS_FIXTURE/outputs" ;;
  '-f json list short sources') cat "$STATUS_FIXTURE/sources" ;;
  subscribe)
    printf '%s\n' "$$" >> "$STATUS_FIXTURE/audio-ready"
    exec cat "$STATUS_FIXTURE/audio-events" ;;
  *) exit 2 ;;
esac
EOF
  cat > "$BIN/inotifywait" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STATUS_FIXTURE/inotify-calls"
[[ $1 == -m && $2 == -q && $3 == -e && $4 == open,close ]] || exit 2
shift 4
for device in "$@"; do [[ -e $device && $device == "$ISLAND_DEV"/video* ]] || exit 2; done
printf '%s\n' "$$" >> "$STATUS_FIXTURE/camera-ready"
exec cat "$STATUS_FIXTURE/camera-events"
EOF
  cat > "$BIN/dunstctl" <<'EOF'
#!/usr/bin/env bash
[[ $* == is-paused ]] || exit 2
printf 'query\n' >> "$STATUS_FIXTURE/dunst-calls"
cat "$STATUS_FIXTURE/paused"
EOF
  cat > "$BIN/dbus-monitor" <<'EOF'
#!/usr/bin/env bash
[[ $# == 3 && $1 == --session ]] || exit 2
[[ $2 == "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path='/org/freedesktop/Notifications'" ]] || exit 2
[[ $3 == "type='signal',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0='org.freedesktop.Notifications'" ]] || exit 2
printf '%s\n' "$$" >> "$STATUS_FIXTURE/dnd-ready"
exec cat "$STATUS_FIXTURE/dnd-events"
EOF
  chmod +x "$BIN/pactl" "$BIN/inotifywait" "$BIN/dunstctl" "$BIN/dbus-monitor"
  export PATH="$BIN"
  EMPTY='{"mic":false,"mic_apps":"","camera":false,"camera_apps":"","dnd":false}'
}

teardown() {
  export PATH="$ORIGINAL_PATH"
  if [[ -n ${listener_pid:-} ]]; then
    kill -TERM "$listener_pid" 2>/dev/null || :
    wait "$listener_pid" 2>/dev/null || :
  fi
  local source pid
  for source in audio camera dnd; do
    if [[ -f $STATUS_FIXTURE/$source-ready ]]; then
      while IFS= read -r pid; do kill "$pid" 2>/dev/null || :; done < "$STATUS_FIXTURE/$source-ready"
    fi
  done
  exec {audio_fd}>&-
  exec {camera_fd}>&-
  exec {dnd_fd}>&-
  exec {output_fd}>&-
}

start_listener() {
  if [[ ${include_own_fd:-0} == 1 ]]; then
    bash -c '
      mkdir -p "$ISLAND_PROC/$$/fd"
      printf "Diri sendiri\n" > "$ISLAND_PROC/$$/comm"
      ln_target="$ISLAND_DEV/video0"
      # Use the test-provided link tool without exposing host desktop tools.
      "$STATUS_LINK" -s "$ln_target" "$ISLAND_PROC/$$/fd/8"
      exec "$1"
    ' bash "$SCRIPTS/status" > "$STATUS_FIXTURE/output" 2> "$STATUS_FIXTURE/stderr" &
  else
    "$SCRIPTS/status" > "$STATUS_FIXTURE/output" 2> "$STATUS_FIXTURE/stderr" &
  fi
  listener_pid=$!
  IFS= read -r -t 2 -u "$output_fd" first
}

wait_ready() {
  local source=$1 attempt
  for ((attempt=0; attempt<200; attempt++)); do
    [[ -s $STATUS_FIXTURE/$source-ready ]] && return 0
    sleep 0.005
  done
  return 1
}

next_event() {
  IFS= read -r -t 2 -u "$output_fd" event
}

assert_silent() {
  ! IFS= read -r -t 0.15 -u "$output_fd" event
}

@test "status is executable and unavailable sources produce one complete initial snapshot" {
  rm "$BIN/pactl" "$BIN/inotifywait" "$BIN/dunstctl" "$BIN/dbus-monitor"
  [ -x "$SCRIPTS/status" ]
  start_listener
  [ "$first" = "$EMPTY" ]
  assert_silent
}

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
  [ "$first" = '{"mic":true,"mic_apps":"Alpha, Aplikasi, Zoom, recorder","camera":false,"camera_apps":"","dnd":false}' ]
}

@test "audio noise does not query while source-output source and server events refresh microphone" {
  start_listener
  [ "$first" = "$EMPTY" ]
  wait_ready audio
  printf '[{"source":66,"properties":{"application.name":"Zoom"}}]\n' > "$STATUS_FIXTURE/outputs"
  printf "%s\n" "Event 'new' on client #9" "Event 'change' on card #2" \
    "Event 'change' on sink-input #3" "Event 'change' on sink #4" >&"$audio_fd"
  assert_silent
  [ "$(sort "$STATUS_FIXTURE/pactl-calls")" = $'-f json list short sources\n-f json list source-outputs\nsubscribe' ]
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
  [ "$first" = '{"mic":false,"mic_apps":"","camera":true,"camera_apps":"Browser, Zoom","dnd":false}' ]
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

@test "initial dunst paused state is true only for literal true" {
  printf 'true\n' > "$STATUS_FIXTURE/paused"
  start_listener
  [ "$first" = '{"mic":false,"mic_apps":"","camera":false,"camera_apps":"","dnd":true}' ]
  wait_ready dnd
  printf 'false\n' > "$STATUS_FIXTURE/paused"
  printf 'signal member=NameOwnerChanged\n' >&"$dnd_fd"
  next_event
  [ "$event" = "$EMPTY" ]
  printf 'unexpected\n' > "$STATUS_FIXTURE/paused"
  printf 'signal member=PropertiesChanged\n' >&"$dnd_fd"
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
  [ "$event" = '{"mic":false,"mic_apps":"","camera":false,"camera_apps":"","dnd":true}' ]
  printf 'signal member=PropertiesChanged\n' >&"$dnd_fd"
  assert_silent
  [ "$(cat "$STATUS_FIXTURE/dunst-calls")" = $'query\nquery\nquery' ]
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
  [ "$event" = '{"mic":false,"mic_apps":"","camera":false,"camera_apps":"","dnd":true}' ]
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
