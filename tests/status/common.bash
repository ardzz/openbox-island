# tests/status/common.bash: fake pactl, inotify, dunst, dbus and bluez feeds for scripts/status.
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
  for tool in bash cat chmod date dirname find jq ln mkdir mkfifo mktemp mv readlink rm rmdir sleep sort timeout touch tr uniq wc; do
    ln -s "$(command -v "$tool")" "$BIN/$tool"
  done
  printf '[]\n' > "$STATUS_FIXTURE/outputs"
  printf '[{"index":66,"name":"alsa_input.test"},{"index":67,"name":"alsa_output.test.monitor"}]\n' > "$STATUS_FIXTURE/sources"
  printf 'false\n' > "$STATUS_FIXTURE/paused"
  mkfifo "$STATUS_FIXTURE/audio-events" "$STATUS_FIXTURE/camera-events" \
    "$STATUS_FIXTURE/dnd-events" "$STATUS_FIXTURE/bluez-events" "$STATUS_FIXTURE/output"
  exec {audio_fd}<> "$STATUS_FIXTURE/audio-events"
  exec {camera_fd}<> "$STATUS_FIXTURE/camera-events"
  exec {dnd_fd}<> "$STATUS_FIXTURE/dnd-events"
  exec {bluez_fd}<> "$STATUS_FIXTURE/bluez-events"
  exec {output_fd}<> "$STATUS_FIXTURE/output"
  cat > "$BIN/pactl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STATUS_FIXTURE/pactl-calls"
case "$*" in
  '-f json list source-outputs') cat "$STATUS_FIXTURE/outputs" ;;
  '-f json list short sources') cat "$STATUS_FIXTURE/sources" ;;
  get-default-sink) cat "$STATUS_FIXTURE/default-sink" ;;
  '-f json list sinks') cat "$STATUS_FIXTURE/sinks" ;;
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
  cat > "$BIN/gdbus" <<'EOF'
#!/usr/bin/env bash
[[ $* == 'monitor --system --dest org.bluez' ]] || exit 2
printf '%s\n' "$$" >> "$STATUS_FIXTURE/bluez-ready"
exec cat "$STATUS_FIXTURE/bluez-events"
EOF
  cat > "$BIN/bluetoothctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STATUS_FIXTURE/bt-calls"
[[ $# == 2 && $1 == info && -e $STATUS_FIXTURE/bt-info ]] || { printf 'Device %s not available\n' "$2"; exit 1; }
cat "$STATUS_FIXTURE/bt-info"
EOF
  chmod +x "$BIN/pactl" "$BIN/inotifywait" "$BIN/dunstctl" "$BIN/dbus-monitor" "$BIN/gdbus" "$BIN/bluetoothctl"
  export PATH="$BIN"
  HP_NONE='"headphone":{"kind":"none","icon":"","name":"","battery":null,"low":false,"label":""}'
  EMPTY='{"mic":false,"mic_apps":"","camera":false,"camera_apps":"","dnd":false,'"$HP_NONE"'}'
}

teardown() {
  export PATH="$ORIGINAL_PATH"
  if [[ -n ${listener_pid:-} ]]; then
    kill -TERM "$listener_pid" 2>/dev/null || :
    wait "$listener_pid" 2>/dev/null || :
  fi
  local source pid
  for source in audio camera dnd bluez; do
    if [[ -f $STATUS_FIXTURE/$source-ready ]]; then
      while IFS= read -r pid; do kill "$pid" 2>/dev/null || :; done < "$STATUS_FIXTURE/$source-ready"
    fi
  done
  exec {audio_fd}>&-
  exec {camera_fd}>&-
  exec {dnd_fd}>&-
  exec {bluez_fd}>&-
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

# count_calls FILE LINE: how many times a fake recorded exactly LINE.
count_calls() {
  local call count=0
  if [[ -f $STATUS_FIXTURE/$1 ]]; then
    while IFS= read -r call; do [[ $call != "$2" ]] || count=$((count + 1)); done < "$STATUS_FIXTURE/$1"
  fi
  printf '%s\n' "$count"
}
