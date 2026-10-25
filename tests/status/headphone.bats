# tests/status/headphone.bats
load ../helpers
load common

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
  [ "$(jq -r '.headphone.battery_icon' <<< "$first")" = $'\U000F0079' ]
  [ "$(count_calls bt-calls "info $BT_MAC")" -ge 1 ]
}

@test "headphone: a bluetooth battery at 20% or below is low from startup" {
  use_sinks "$BT_SINK" '' "$BT_MAC"
  bt_info 'ULT WEAR' 15
  start_listener
  [ "$(headphone "$first")" = '["bt","ULT WEAR",15,true,"ULT WEAR · 15%"]' ]
  [ "$(jq -r '.headphone.battery_icon' <<< "$first")" = $'\U000F007A' ]
}

@test "headphone: an unknown battery shows the name only and the MAC falls back to the sink name" {
  use_sinks "$BT_SINK"
  bt_info 'ULT WEAR (Reky)'
  start_listener
  [ "$(headphone "$first")" = '["bt","ULT WEAR (Reky)",null,false,"ULT WEAR (Reky)"]' ]
  [ "$(jq -r '.headphone.battery_icon' <<< "$first")" = '' ]
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
