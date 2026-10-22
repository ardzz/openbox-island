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

@test "status is executable and unavailable sources produce one complete initial snapshot" {
  rm "$BIN/pactl" "$BIN/inotifywait" "$BIN/dunstctl" "$BIN/dbus-monitor" "$BIN/gdbus" "$BIN/bluetoothctl"
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

# count_calls FILE LINE: how many times a fake recorded exactly LINE.
count_calls() {
  local call count=0
  if [[ -f $STATUS_FIXTURE/$1 ]]; then
    while IFS= read -r call; do [[ $call != "$2" ]] || count=$((count + 1)); done < "$STATUS_FIXTURE/$1"
  fi
  printf '%s\n' "$count"
}

BT_SINK=bluez_output.A8_E6_E8_A6_10_77.1
BT_MAC=A8:E6:E8:A6:10:77

# use_sinks DEFAULT [ANALOG_PORT] [BT_ADDRESS]: built-in analog, HDMI and BT headset sinks; DEFAULT is the default sink.
use_sinks() {
  local address=''
  [[ -z ${3:-} ]] || address=",\"properties\":{\"api.bluez5.address\":\"$3\"}"
  printf '%s\n' "$1" > "$STATUS_FIXTURE/default-sink"
  cat > "$STATUS_FIXTURE/sinks" <<EOF
[{"name":"alsa_output.pci-0000_00_1f.3.analog-stereo","description":"Built-in Audio Analog Stereo","active_port":"${2:-analog-output-speaker}",
  "ports":[{"name":"analog-output-speaker","description":"Speakers","type":"Speaker"},
           {"name":"analog-output-headphones","description":"Headphones","type":"Headphones"}]},
 {"name":"alsa_output.pci-0000_01_00.1.hdmi-stereo","description":"Built-in Audio Digital Stereo (HDMI)","active_port":"hdmi-output-0",
  "ports":[{"name":"hdmi-output-0","description":"HDMI / DisplayPort","type":"HDMI"}]},
 {"name":"$BT_SINK","description":"ULT WEAR","active_port":"headset-output",
  "ports":[{"name":"headset-output","description":"Headphones","type":"Headset"}]$address}]
EOF
}

# bt_info ALIAS [PERCENT]: what bluetoothctl info reports for the headset.
bt_info() {
  {
    printf 'Device %s (public)\n\tName: ULT WEAR\n\tAlias: %s\n\tIcon: audio-headset\n\tConnected: yes\n' "$BT_MAC" "$1"
    if [[ -n ${2:-} ]]; then printf '\tBattery Percentage: 0x%02x (%s)\n' "$2" "$2"; fi
  } > "$STATUS_FIXTURE/bt-info.new"
  # A snapshot still running must never read a half-written file.
  mv "$STATUS_FIXTURE/bt-info.new" "$STATUS_FIXTURE/bt-info"
}

# settle_bluetooth: wait until the audio and bluez workers both took their startup snapshot.
settle_bluetooth() {
  local attempt
  wait_ready audio && wait_ready bluez || return
  for ((attempt=0; attempt<200; attempt++)); do
    (( $(count_calls bt-calls "info $BT_MAC") >= 2 )) && return 0
    sleep 0.005
  done
  return 1
}

headphone() {
  jq -c '.headphone | [.kind,.name,.battery,.low,.label]' <<< "$1"
}

battery_signal() {
  printf "/org/bluez/hci0/dev_A8_E6_E8_A6_10_77: org.freedesktop.DBus.Properties.PropertiesChanged ('org.bluez.Battery1', {'Percentage': <byte 0x%02x>}, @as [])\n" "$1" >&"$bluez_fd"
}

@test "headphone: an already connected bluetooth headset shows its alias, battery and BT icon at startup" {
  use_sinks "$BT_SINK" '' "$BT_MAC"
  bt_info 'ULT WEAR' 90
  start_listener
  [ "$(headphone "$first")" = '["bt","ULT WEAR",90,false,"ULT WEAR · 90%"]' ]
  [ "$(jq -r '.headphone.icon' <<< "$first")" = $'\U000F0970' ]
  [ "$(count_calls bt-calls "info $BT_MAC")" -ge 1 ]
}

@test "headphone: a bluetooth battery at 20% or below is low from startup" {
  use_sinks "$BT_SINK" '' "$BT_MAC"
  bt_info 'ULT WEAR' 15
  start_listener
  [ "$(headphone "$first")" = '["bt","ULT WEAR",15,true,"ULT WEAR · 15%"]' ]
}

@test "headphone: an unknown battery shows the name only and the MAC falls back to the sink name" {
  use_sinks "$BT_SINK"
  bt_info 'ULT WEAR (Reky)'
  start_listener
  [ "$(headphone "$first")" = '["bt","ULT WEAR (Reky)",null,false,"ULT WEAR (Reky)"]' ]
  [ "$(count_calls bt-calls "info $BT_MAC")" -ge 1 ]
}

@test "headphone: without bluetoothctl the bluetooth sink description names the headset" {
  rm "$BIN/bluetoothctl"
  use_sinks "$BT_SINK" '' "$BT_MAC"
  start_listener
  [ "$(headphone "$first")" = '["bt","ULT WEAR",null,false,"ULT WEAR"]' ]
  [ "$(jq -r '.headphone.icon' <<< "$first")" = $'\U000F0970' ]
}

@test "headphone: a wired headphone port shows the plain headphone icon without asking bluez" {
  use_sinks alsa_output.pci-0000_00_1f.3.analog-stereo analog-output-headphones
  start_listener
  [ "$(headphone "$first")" = '["wired","Headphones",null,false,"Headphones"]' ]
  [ "$(jq -r '.headphone.icon' <<< "$first")" = $'\U000F02CB' ]
  [ "$(count_calls bt-calls "info $BT_MAC")" -eq 0 ]
}

@test "headphone: speakers and HDMI outputs show nothing" {
  use_sinks alsa_output.pci-0000_00_1f.3.analog-stereo
  start_listener
  [ "$first" = "$EMPTY" ]
  wait_ready audio
  use_sinks alsa_output.pci-0000_01_00.1.hdmi-stereo
  printf "Event 'change' on server\n" >&"$audio_fd"
  assert_silent
}

@test "headphone: server and sink events follow bluetooth to wired to speakers and back" {
  use_sinks "$BT_SINK" '' "$BT_MAC"
  bt_info 'ULT WEAR' 90
  start_listener
  [ "$(headphone "$first")" = '["bt","ULT WEAR",90,false,"ULT WEAR · 90%"]' ]
  wait_ready audio
  use_sinks alsa_output.pci-0000_00_1f.3.analog-stereo analog-output-headphones "$BT_MAC"
  printf "Event 'change' on server\n" >&"$audio_fd"
  next_event
  [ "$(headphone "$event")" = '["wired","Headphones",null,false,"Headphones"]' ]
  [ "$(jq -r '.headphone.icon' <<< "$event")" = $'\U000F02CB' ]
  use_sinks alsa_output.pci-0000_00_1f.3.analog-stereo analog-output-speaker "$BT_MAC"
  printf "Event 'change' on sink #57\n" >&"$audio_fd"
  next_event
  [ "$event" = "$EMPTY" ]
  use_sinks "$BT_SINK" '' "$BT_MAC"
  printf "Event 'new' on sink #58\n" >&"$audio_fd"
  next_event
  [ "$(headphone "$event")" = '["bt","ULT WEAR",90,false,"ULT WEAR · 90%"]' ]
  assert_silent
}

@test "headphone: client, card and sink-input events do not re-read the sinks" {
  use_sinks "$BT_SINK" '' "$BT_MAC"
  bt_info 'ULT WEAR' 90
  start_listener
  wait_ready audio
  wait_ready bluez
  local before
  before=$(count_calls pactl-calls '-f json list sinks')
  printf "%s\n" "Event 'new' on client #9" "Event 'change' on card #2" "Event 'change' on sink-input #3" >&"$audio_fd"
  assert_silent
  [ "$(count_calls pactl-calls '-f json list sinks')" -eq "$before" ]
}

@test "headphone: bluez battery signals refresh the percentage across the low threshold" {
  use_sinks "$BT_SINK" '' "$BT_MAC"
  bt_info 'ULT WEAR' 90
  start_listener
  settle_bluetooth
  bt_info 'ULT WEAR' 20
  battery_signal 20
  next_event
  [ "$(headphone "$event")" = '["bt","ULT WEAR",20,true,"ULT WEAR · 20%"]' ]
  bt_info 'ULT WEAR' 21
  battery_signal 21
  next_event
  [ "$(headphone "$event")" = '["bt","ULT WEAR",21,false,"ULT WEAR · 21%"]' ]
  assert_silent
}

@test "headphone: bluez Connected signals refresh while other device properties are ignored" {
  use_sinks "$BT_SINK" '' "$BT_MAC"
  bt_info 'ULT WEAR' 90
  start_listener
  settle_bluetooth
  local before
  before=$(count_calls bt-calls "info $BT_MAC")
  printf "%s\n" "/org/bluez/hci0/dev_A8_E6_E8_A6_10_77: org.freedesktop.DBus.Properties.PropertiesChanged ('org.bluez.Device1', {'RSSI': <int16 -60>}, @as [])" >&"$bluez_fd"
  assert_silent
  [ "$(count_calls bt-calls "info $BT_MAC")" -eq "$before" ]
  use_sinks alsa_output.pci-0000_00_1f.3.analog-stereo
  printf "%s\n" "/org/bluez/hci0/dev_A8_E6_E8_A6_10_77: org.freedesktop.DBus.Properties.PropertiesChanged ('org.bluez.Device1', {'Connected': <false>}, @as [])" >&"$bluez_fd"
  next_event
  [ "$event" = "$EMPTY" ]
}
