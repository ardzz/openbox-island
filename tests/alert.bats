load helpers

setup() {
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export ALERT_FIXTURE="$BATS_TEST_TMPDIR"
  export ISLAND_HWMON="$BATS_TEST_TMPDIR/hwmon" ISLAND_LEDS="$BATS_TEST_TMPDIR/leds"
  export ISLAND_SCREENSHOT_DIR="$BATS_TEST_TMPDIR/shots"
  export ISLAND_PLATFORM_PROFILE="$BATS_TEST_TMPDIR/platform_profile"
  unset ISLAND_TEMP_CPU ISLAND_TEMP_GPU
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN" "$XDG_RUNTIME_DIR" "$ISLAND_HWMON" "$ISLAND_LEDS"
  export PATH="$BIN:$PATH"
  source "$SCRIPTS/alert"
  CLEAR='{"kind":"","icon":"","text":"","value":"","level":-1,"image":""}'
  RESULT="$BATS_TEST_TMPDIR/result"
}

teardown() {
  if [[ -n ${listener_pid:-} ]]; then
    kill "$listener_pid" 2>/dev/null || :
    wait "$listener_pid" 2>/dev/null || :
  fi
}

@test "initial audio, brightness, and battery samples produce no alert" {
  {
    audio_update 42 no no
    brightness_update 17.00
    battery_update discharging 76
  } > "$RESULT"
  [ ! -s "$RESULT" ]
}

@test "volume changes use the first channel percent and the low mid high boundaries" {
  {
    audio_update 10 no no
    audio_update 33 no no
    audio_update 34 no no
    audio_update 66 no no
    audio_update 67 no no
  } > "$RESULT"
  [ "$(jq -sc 'map([.kind,.text,.value,.level])' "$RESULT")" = '[["volume","Volume","33%",33],["volume","Volume","34%",34],["volume","Volume","66%",66],["volume","Volume","67%",67]]' ]
  [ "$(jq -sr 'map(.icon)|join("|")' "$RESULT")" = $'\uF026|\uF027|\uF027|\uF028' ]
}

@test "sink mute changes emit Bisu even when the volume is unchanged" {
  {
    audio_update 42 no no
    audio_update 42 yes no
    audio_update 42 yes no
    audio_update 42 no no
  } > "$RESULT"
  [ "$(jq -sc 'map([.kind,.text,.value,.level])' "$RESULT")" = '[["volume","Bisu","42%",42],["volume","Volume","42%",42]]' ]
  [ "$(jq -sr '.[0].icon' "$RESULT")" = $'\U000F0581' ]
}

@test "source mute changes emit microphone state with no percentage" {
  {
    audio_update 42 no no
    audio_update 42 no yes
    audio_update 42 no yes
    audio_update 42 no no
  } > "$RESULT"
  [ "$(jq -sc 'map([.kind,.text,.value,.level])' "$RESULT")" = '[["mic","Mikrofon mati","",-1],["mic","Mikrofon nyala","",-1]]' ]
  [ "$(jq -sr 'map(.icon)|join("|")' "$RESULT")" = $'\U000F036D|\U000F036C' ]
}

@test "brightness truncates decimals and ignores changes within the same integer percent" {
  {
    brightness_update 17.00
    brightness_update 17.99
    brightness_update 33.99
    brightness_update 34.01
    brightness_update 67.90
  } > "$RESULT"
  [ "$(jq -sc 'map([.kind,.text,.value,.level])' "$RESULT")" = '[["brightness","Kecerahan","33%",33],["brightness","Kecerahan","34%",34],["brightness","Kecerahan","67%",67]]' ]
  [ "$(jq -sr 'map(.icon)|join("|")' "$RESULT")" = $'\U000F00DE|\U000F00DF|\U000F00E0' ]
}

@test "battery transitions emit once each and plugging in uses the charging kind" {
  {
    battery_update discharging 76
    battery_update charging 76
    battery_update charging 77
    battery_update discharging 77
    battery_update pending-charge 78
    battery_update discharging 78
    battery_update fully-charged 100
    battery_update fully-charged 100
    battery_update discharging 100
  } > "$RESULT"
  [ "$(jq -sc 'map([.kind,.text,.value,.level])' "$RESULT")" = '[["charging","Mengisi daya","76%",76],["battery","Charger dicabut","77%",77],["battery","Charger dicabut","78%",78],["battery","Baterai penuh","100%",100],["battery","Charger dicabut","100%",100]]' ]
  [ "$(jq -sr 'map(.icon)|join("|")' "$RESULT")" = $'\U000F0084|\U000F0079|\U000F0079|\U000F0079|\U000F0079' ]
  [ "$(jq -sc 'map(.image)|unique' "$RESULT")" = '[""]' ]
}

@test "low and critical battery crossings do not repeat below their thresholds" {
  {
    battery_update discharging 21
    battery_update discharging 20
    battery_update discharging 20
    battery_update discharging 19
    battery_update discharging 11
    battery_update discharging 10
    battery_update discharging 9
  } > "$RESULT"
  [ "$(jq -sc 'map([.kind,.text,.value,.level])' "$RESULT")" = '[["battery-low","Baterai lemah","20%",20],["battery-low","Baterai kritis","10%",10]]' ]
  [ "$(jq -sr 'map(.icon)|join("|")' "$RESULT")" = $'\U000F12A1|\U000F12A1' ]
}

@test "starting with a low battery or crossing thresholds while charging is silent" {
  {
    battery_update discharging 9
    battery_update discharging 8
    battery_update charging 21
    battery_update charging 20
    battery_update charging 10
  } > "$RESULT"
  [ "$(jq -sc 'map(.text)' "$RESULT")" = '["Mengisi daya"]' ]
}

make_fakes() {
  printf '42\n' > "$ALERT_FIXTURE/volume"
  printf 'no\n' > "$ALERT_FIXTURE/mute"
  printf 'no\n' > "$ALERT_FIXTURE/mic"
  printf '17.00\n' > "$ALERT_FIXTURE/brightness"
  printf 'discharging\n' > "$ALERT_FIXTURE/battery-state"
  printf '76\n' > "$ALERT_FIXTURE/battery-percent"
  write_sinks alsa_output.pci-0000_00_1f.3.analog-stereo
  mkfifo "$ALERT_FIXTURE/audio-events" "$ALERT_FIXTURE/brightness-events" \
    "$ALERT_FIXTURE/battery-events" "$ALERT_FIXTURE/wifi-events" \
    "$ALERT_FIXTURE/bluetooth-events" "$ALERT_FIXTURE/screenshot-events"
  printf 'Device AA:BB:CC:DD:EE:01 Keyboard K380\n' > "$ALERT_FIXTURE/bt-connected"
  printf 'Device AA:BB:CC:DD:EE:01 (public)\n\tName: K380\n\tAlias: Keyboard K380\n\tIcon: input-keyboard\n\tConnected: yes\n' \
    > "$ALERT_FIXTURE/bt-info-AA:BB:CC:DD:EE:01"
  printf 'Device F4:93:B1:9A:5C:21 (public)\n\tName: WH-1000XM4\n\tAlias: WH-1000XM4\n\tClass: 0x00240404\n\tIcon: audio-headset\n\tConnected: yes\n\tBattery Percentage: 0x50 (80)\n' \
    > "$ALERT_FIXTURE/bt-info-F4:93:B1:9A:5C:21"
  make_hwmon hwmon3 'CPU Temperature:50000' 'GPU Temperature:50000'
  mkdir -p "$ISLAND_LEDS/input3::capslock"
  printf '0\n' > "$ISLAND_LEDS/input3::capslock/brightness"
  printf 'performance\n' > "$ISLAND_PLATFORM_PROFILE"
  cat > "$BIN/pactl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$ALERT_FIXTURE/audio-queries"
case $1 in
  subscribe) touch "$ALERT_FIXTURE/audio-ready"; exec cat "$ALERT_FIXTURE/audio-events" ;;
  get-sink-volume) read -r n < "$ALERT_FIXTURE/volume"; printf 'Volume: front-left: 27525 / %s%% / -23 dB, front-right: 65536 / 100%% / 0 dB\n' "$n" ;;
  get-sink-mute) printf 'Mute: '; cat "$ALERT_FIXTURE/mute" ;;
  get-source-mute) printf 'Mute: '; cat "$ALERT_FIXTURE/mic" ;;
  get-default-sink) cat "$ALERT_FIXTURE/default-sink" ;;
  -f) [[ $* == '-f json list sinks' ]] || exit 2; cat "$ALERT_FIXTURE/sinks.json" ;;
  *) exit 2 ;;
esac
EOF
  cat > "$BIN/light" <<'EOF'
#!/usr/bin/env bash
[[ $* == -G ]] || exit 2
cat "$ALERT_FIXTURE/brightness"
EOF
  cat > "$BIN/udevadm" <<'EOF'
#!/usr/bin/env bash
[[ $* == 'monitor --udev --subsystem-match=backlight' ]] || exit 2
touch "$ALERT_FIXTURE/brightness-ready"
exec cat "$ALERT_FIXTURE/brightness-events"
EOF
  cat > "$BIN/upower" <<'EOF'
#!/usr/bin/env bash
case $1 in
  -e) printf '/org/freedesktop/UPower/devices/line_power_AC\n/org/freedesktop/UPower/devices/battery_BAT1\n' ;;
  -i) [[ $2 == /org/freedesktop/UPower/devices/battery_BAT1 ]] || exit 2
      printf '    state:               '; cat "$ALERT_FIXTURE/battery-state"
      read -r n < "$ALERT_FIXTURE/battery-percent"; printf '    percentage:          %s%%\n' "$n" ;;
  --monitor) touch "$ALERT_FIXTURE/battery-ready"; exec cat "$ALERT_FIXTURE/battery-events" ;;
  *) exit 2 ;;
esac
EOF
  cat > "$BIN/nmcli" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$ALERT_FIXTURE/wifi-queries"
case "$*" in
  '-t -f DEVICE,TYPE device') printf 'docker0:bridge\nveth123:ethernet\ntun0:tun\np2p-dev-wlan0:wifi-p2p\nwlan0:wifi\n' ;;
  '-t -g GENERAL.STATE device show wlan0') printf '30 (disconnected)\n' ;;
  '-t -g GENERAL.CONNECTION device show wlan0') printf 'Rumah "A" \\ jaringan\n' ;;
  monitor) touch "$ALERT_FIXTURE/wifi-ready"; exec cat "$ALERT_FIXTURE/wifi-events" ;;
  *) exit 2 ;;
esac
EOF
  cat > "$BIN/bluetoothctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$ALERT_FIXTURE/bt-queries"
case $1 in
  devices) [[ $# == 2 && $2 == Connected ]] || exit 2; cat "$ALERT_FIXTURE/bt-connected" ;;
  info) [[ $# == 2 && -e $ALERT_FIXTURE/bt-info-$2 ]] || { printf 'Device %s not available\n' "$2"; exit 1; }
        cat "$ALERT_FIXTURE/bt-info-$2" ;;
  *) exit 2 ;;
esac
EOF
  cat > "$BIN/gdbus" <<'EOF'
#!/usr/bin/env bash
[[ $* == 'monitor --system --dest org.bluez' ]] || exit 2
touch "$ALERT_FIXTURE/bluetooth-ready"
exec cat "$ALERT_FIXTURE/bluetooth-events"
EOF
  cat > "$BIN/inotifywait" <<'EOF'
#!/usr/bin/env bash
[[ $# == 7 && $1 == -m && $2 == -q && $3 == -e && $4 == close_write,moved_to && $5 == --format && $6 == %w%f ]] || exit 2
[[ $7 == "$ISLAND_SCREENSHOT_DIR" && -d $7 ]] || exit 2
touch "$ALERT_FIXTURE/screenshot-ready"
exec cat "$ALERT_FIXTURE/screenshot-events"
EOF
  chmod +x "$BIN/pactl" "$BIN/light" "$BIN/udevadm" "$BIN/upower" "$BIN/nmcli" \
    "$BIN/bluetoothctl" "$BIN/gdbus" "$BIN/inotifywait"
}

# make_hwmon DIR 'LABEL:MILLIDEGREES'...: one fake hwmon device with labelled temp inputs.
make_hwmon() {
  local dir="$ISLAND_HWMON/$1" spec n=0
  shift
  mkdir -p "$dir"
  printf 'fake\n' > "$dir/name"
  for spec in "$@"; do
    n=$((n + 1))
    printf '%s\n' "${spec%:*}" > "$dir/temp${n}_label"
    printf '%s\n' "${spec##*:}" > "$dir/temp${n}_input"
  done
}

@test "fractional battery snapshots truncate percentages and retain charging transitions" {
  make_fakes
  battery_path=/org/freedesktop/UPower/devices/battery_BAT1
  {
    printf '21.9\n' > "$ALERT_FIXTURE/battery-percent"
    battery_snapshot
    printf '19.5\n' > "$ALERT_FIXTURE/battery-percent"
    battery_snapshot
    printf 'charging\n' > "$ALERT_FIXTURE/battery-state"
    battery_snapshot
    printf 'discharging\n' > "$ALERT_FIXTURE/battery-state"
    printf '09.9\n' > "$ALERT_FIXTURE/battery-percent"
    battery_snapshot
  } > "$RESULT"
  [ "$battery_value" -eq 9 ]
  [ "$battery_state" = discharging ]
  [ "$(jq -sc 'map([.kind,.text,.value,.level])' "$RESULT")" = '[["battery-low","Baterai lemah","19%",19],["charging","Mengisi daya","19%",19],["battery","Charger dicabut","9%",9],["battery-low","Baterai kritis","9%",9]]' ]
}

@test "each monitor connection silently refreshes its baseline before queued events" {
  make_fakes
  cat > "$BIN/queued_monitor" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1"
sleep 0.05
EOF
  chmod +x "$BIN/queued_monitor"
  battery_path=/org/freedesktop/UPower/devices/battery_BAT1
  {
    monitor_stream audio_event queued_monitor "Event 'change' on server"
    monitor_stream brightness_event queued_monitor 'UDEV backlight'
    monitor_stream battery_event queued_monitor "device changed: $battery_path"
    monitor_stream wifi_event queued_monitor 'wlan0: disconnected'
  } > "$RESULT"
  [ ! -s "$RESULT" ]
  printf '55\n' > "$ALERT_FIXTURE/volume"
  printf 'yes\n' > "$ALERT_FIXTURE/mic"
  printf '34.5\n' > "$ALERT_FIXTURE/brightness"
  printf '19\n' > "$ALERT_FIXTURE/battery-percent"
  printf 'charging\n' > "$ALERT_FIXTURE/battery-state"
  wifi_event 'wlan0: connected' > /dev/null
  {
    monitor_stream audio_event queued_monitor "Event 'change' on server"
    monitor_stream brightness_event queued_monitor 'UDEV backlight'
    monitor_stream battery_event queued_monitor "device changed: $battery_path"
    monitor_stream wifi_event queued_monitor 'wlan0: disconnected'
  } >> "$RESULT"
  [ ! -s "$RESULT" ]
  [ "$audio_volume" -eq 55 ]
  [ "$audio_mic" = yes ]
  [ "$brightness_value" -eq 34 ]
  [ "$battery_state" = charging ]
  [ "$battery_value" -eq 19 ]
  [ "${wifi_states[wlan0]}" = disconnected ]
  {
    printf '60\n' > "$ALERT_FIXTURE/volume"
    audio_event "Event 'change' on sink #65"
    printf '40\n' > "$ALERT_FIXTURE/brightness"
    brightness_event 'UDEV backlight'
    printf 'discharging\n' > "$ALERT_FIXTURE/battery-state"
    battery_event "device changed: $battery_path"
    wifi_event 'wlan0: connected'
  } >> "$RESULT"
  [ "$(jq -sc 'map(.kind)' "$RESULT")" = '["volume","brightness","battery","wifi"]' ]
}

@test "audio client card and stream noise never triggers another query" {
  make_fakes
  audio_snapshot > "$RESULT"
  before=$(cat "$ALERT_FIXTURE/audio-queries")
  {
    audio_event "Event 'new' on client #10987"
    audio_event "Event 'change' on card #54"
    audio_event "Event 'change' on sink-input #65"
    audio_event "Event 'change' on source-output #66"
  } >> "$RESULT"
  [ ! -s "$RESULT" ]
  [ "$(cat "$ALERT_FIXTURE/audio-queries")" = "$before" ]
  printf '51\n' > "$ALERT_FIXTURE/volume"
  audio_event "Event 'change' on sink #65" >> "$RESULT"
  [ "$(jq -c '[.kind,.value,.level]' "$RESULT")" = '["volume","51%",51]' ]
}

# write_sinks DEFAULT [BUILTIN_PORT]: fake default sink and `pactl -f json list sinks` output.
write_sinks() {
  printf '%s\n' "$1" > "$ALERT_FIXTURE/default-sink"
  jq -n --arg port "${2:-analog-output-speaker}" '[
    {index:65, name:"alsa_output.pci-0000_00_1f.3.analog-stereo", description:"Built-in Audio Analog Stereo", active_port:$port,
     ports:[{name:"analog-output-speaker", description:"Speakers"}, {name:"analog-output-headphones", description:"Headphones"}]},
    {index:70, name:"alsa_output.pci-0000_01_00.1.hdmi-stereo", description:"Built-in Audio Digital Stereo (HDMI)", active_port:"hdmi-output-0",
     ports:[{name:"hdmi-output-0", description:"HDMI / DisplayPort"}]},
    {index:71, name:"bluez_output.F4_93_B1_9A_5C_21.1", description:"WH-1000XM4", active_port:"headphone-output",
     ports:[{name:"headphone-output", description:"Headphone"}]},
    {index:72, name:"alsa_output.usb-Logitech_G435-00.analog-stereo", description:"G435 Wireless Gaming Headset Analog Stereo", active_port:"analog-output",
     ports:[{name:"analog-output", description:"Analog Output"}]},
    {index:73, name:"alsa_output.usb-Dock-00.analog-stereo", description:"USB Dock Analog Stereo", active_port:"displayport-output",
     ports:[{name:"analog-output-lineout", description:"Line Out"}, {name:"displayport-output", description:"DisplayPort 1"}]}
  ]' > "$ALERT_FIXTURE/sinks.json"
}

@test "audio output switches emit the device with its icon and the port only for multi-port sinks" {
  make_fakes
  audio_snapshot > "$RESULT"
  {
    write_sinks alsa_output.pci-0000_00_1f.3.analog-stereo analog-output-headphones
    audio_event "Event 'change' on sink #65"
    write_sinks alsa_output.pci-0000_01_00.1.hdmi-stereo
    audio_event "Event 'change' on server"
    write_sinks bluez_output.F4_93_B1_9A_5C_21.1
    audio_event "Event 'change' on server"
    write_sinks alsa_output.usb-Logitech_G435-00.analog-stereo
    audio_event "Event 'change' on server"
    write_sinks alsa_output.usb-Dock-00.analog-stereo
    audio_event "Event 'change' on server"
    write_sinks alsa_output.pci-0000_00_1f.3.analog-stereo
    audio_event "Event 'change' on server"
  } >> "$RESULT"
  [ "$(jq -sc 'map([.kind,.text,.value,.level,.image])' "$RESULT")" = '[["output","Output audio","Headphones",-1,""],["output","Output audio","Built-in Audio Digital Stereo (HDMI)",-1,""],["output","Output audio","WH-1000XM4",-1,""],["output","Output audio","G435 Wireless Gaming Headset Analog Stereo",-1,""],["output","Output audio","DisplayPort 1",-1,""],["output","Output audio","Speakers",-1,""]]' ]
  [ "$(jq -sr 'map(.icon)|join("|")' "$RESULT")" = $'\U000F02CB|\U000F0379|\U000F0970|\U000F02CB|\U000F0379|\U000F04C3' ]
}

@test "unchanged outputs stay silent and only sink or server events query the sinks once each" {
  make_fakes
  audio_snapshot > "$RESULT"
  : > "$ALERT_FIXTURE/audio-queries"
  {
    audio_event "Event 'change' on server"
    printf '51\n' > "$ALERT_FIXTURE/volume"
    audio_event "Event 'change' on sink #65"
    printf 'yes\n' > "$ALERT_FIXTURE/mic"
    audio_event "Event 'change' on source #66"
  } >> "$RESULT"
  [ "$(jq -sc 'map(.kind)' "$RESULT")" = '["volume","mic"]' ]
  [ "$(cat "$ALERT_FIXTURE/audio-queries")" = "$(printf '%s\n' \
    'get-sink-volume @DEFAULT_SINK@' 'get-sink-mute @DEFAULT_SINK@' 'get-source-mute @DEFAULT_SOURCE@' \
    get-default-sink '-f json list sinks' \
    'get-sink-volume @DEFAULT_SINK@' 'get-sink-mute @DEFAULT_SINK@' 'get-source-mute @DEFAULT_SOURCE@' \
    get-default-sink '-f json list sinks' \
    'get-sink-volume @DEFAULT_SINK@' 'get-sink-mute @DEFAULT_SINK@' 'get-source-mute @DEFAULT_SOURCE@')" ]
}

@test "audio monitor reconnect takes the output baseline silently" {
  make_fakes
  cat > "$BIN/queued_monitor" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1"
sleep 0.05
EOF
  chmod +x "$BIN/queued_monitor"
  monitor_stream audio_event queued_monitor "Event 'change' on server" > "$RESULT"
  write_sinks bluez_output.F4_93_B1_9A_5C_21.1
  monitor_stream audio_event queued_monitor "Event 'change' on server" >> "$RESULT"
  [ ! -s "$RESULT" ]
  write_sinks alsa_output.pci-0000_00_1f.3.analog-stereo
  audio_event "Event 'change' on server" >> "$RESULT"
  [ "$(jq -c '[.kind,.value]' "$RESULT")" = '["output","Speakers"]' ]
}

@test "volume alerts keep working when pactl cannot list sinks as JSON" {
  make_fakes
  rm "$ALERT_FIXTURE/sinks.json"
  audio_snapshot > "$RESULT" 2>/dev/null
  printf '51\n' > "$ALERT_FIXTURE/volume"
  audio_event "Event 'change' on server" >> "$RESULT" 2>/dev/null
  [ "$(jq -c '[.kind,.value]' "$RESULT")" = '["volume","51%"]' ]
}

@test "wifi only handles wifi devices and deduplicates state while preserving connection text" {
  make_fakes
  wifi_snapshot > "$RESULT"
  before=$(cat "$ALERT_FIXTURE/wifi-queries")
  {
    wifi_event 'docker0: connected'
    wifi_event 'veth123: disconnected'
    wifi_event 'tun0: connected'
    wifi_event 'p2p-dev-wlan0: connected'
    wifi_event "Connectivity is now 'full'"
    wifi_event 'NetworkManager is running'
  } >> "$RESULT"
  [ ! -s "$RESULT" ]
  [ "$(cat "$ALERT_FIXTURE/wifi-queries")" = "$before" ]
  {
    wifi_event 'wlan0: connected'
    wifi_event 'wlan0: connected'
    wifi_event "wlan0: using connection 'Home'"
    wifi_event 'wlan0: disconnected'
    wifi_event 'wlan0: disconnected'
  } >> "$RESULT"
  [ "$(jq -sc 'map([.kind,.text,.level])' "$RESULT")" = '[["wifi","Wi-Fi tersambung",-1],["wifi","Wi-Fi terputus",-1]]' ]
  [ "$(jq -sr '.[0].value' "$RESULT")" = 'Rumah "A" \ jaringan' ]
  [ "$(jq -sr '.[1].value' "$RESULT")" = '' ]
  [ "$(jq -sr 'map(.icon)|join("|")' "$RESULT")" = $'\U000F0928|\U000F092D' ]
}

bt_line() {
  printf "/org/bluez/hci0/dev_%s: org.freedesktop.DBus.Properties.PropertiesChanged ('org.bluez.%s', {%s}, @as [])" "$1" "$2" "$3"
}

@test "bluetooth connection changes emit per device with alias battery and device icon" {
  make_fakes
  bluetooth_snapshot > "$RESULT"
  {
    bluetooth_event "$(bt_line AA_BB_CC_DD_EE_01 Device1 "'Connected': <true>")"
    bluetooth_event "$(bt_line F4_93_B1_9A_5C_21 Device1 "'ServicesResolved': <true>, 'Connected': <true>")"
    bluetooth_event "$(bt_line F4_93_B1_9A_5C_21 Device1 "'Connected': <true>")"
    bluetooth_event "$(bt_line F4_93_B1_9A_5C_21 Device1 "'Connected': <false>, 'ServicesResolved': <false>")"
    bluetooth_event "$(bt_line AA_BB_CC_DD_EE_01 Device1 "'Connected': <false>")"
    bluetooth_event "$(bt_line AA_BB_CC_DD_EE_01 Device1 "'Connected': <false>")"
  } >> "$RESULT"
  [ "$(jq -sc 'map([.kind,.text,.value,.level,.image])' "$RESULT")" = '[["bluetooth","Bluetooth tersambung","WH-1000XM4 · 80%",-1,""],["bluetooth","Bluetooth terputus","WH-1000XM4",-1,""],["bluetooth","Bluetooth terputus","Keyboard K380",-1,""]]' ]
  [ "$(jq -sr 'map(.icon)|join("|")' "$RESULT")" = $'\U000F02CB|\U000F02CB|\U000F030C' ]
}

@test "bluetooth ignores signals other than a device Connected change without querying" {
  make_fakes
  bluetooth_snapshot > "$RESULT"
  {
    bluetooth_event "$(bt_line F4_93_B1_9A_5C_21 Device1 "'RSSI': <int16 -60>")"
    bluetooth_event "$(bt_line F4_93_B1_9A_5C_21 Battery1 "'Percentage': <byte 0x4f>")"
    bluetooth_event "/org/bluez/hci0/dev_F4_93_B1_9A_5C_21/sep1/fd0: org.freedesktop.DBus.Properties.PropertiesChanged ('org.bluez.MediaTransport1', {'State': <'active'>}, @as [])"
    bluetooth_event "/org/bluez/hci0: org.freedesktop.DBus.Properties.PropertiesChanged ('org.bluez.Adapter1', {'Discovering': <true>}, @as [])"
    bluetooth_event 'Monitoring signals from all objects owned by org.bluez'
  } >> "$RESULT"
  [ ! -s "$RESULT" ]
  [ "$(cat "$ALERT_FIXTURE/bt-queries")" = 'devices Connected' ]
}

@test "bluetooth icons map audio gaming mouse keyboard and phone devices with a bluetooth fallback" {
  make_fakes
  bluetooth_snapshot > /dev/null
  local icon
  for icon in audio-headphones audio-headset audio-card input-gaming input-mouse input-keyboard phone computer ''; do
    {
      printf 'Device 11:22:33:44:55:66 (public)\n\tAlias: Perangkat\n'
      [[ -z $icon ]] || printf '\tIcon: %s\n' "$icon"
    } > "$ALERT_FIXTURE/bt-info-11:22:33:44:55:66"
    bluetooth_event "$(bt_line 11_22_33_44_55_66 Device1 "'Connected': <true>")"
    bluetooth_event "$(bt_line 11_22_33_44_55_66 Device1 "'Connected': <false>")"
  done > "$RESULT"
  [ "$(jq -sr 'map(select(.text == "Bluetooth tersambung") | .icon)|join("|")' "$RESULT")" = $'\U000F02CB|\U000F02CB|\U000F02CB|\U000F0297|\U000F037D|\U000F030C|\U000F011C|\U000F00AF|\U000F00AF' ]
  [ "$(jq -sc 'map(.value)|unique' "$RESULT")" = '["Perangkat"]' ]
}

@test "new screenshot images emit a thumbnail alert and other files are ignored" {
  local dir=/home/user/Gambar/Screenshots
  {
    screenshot_event "$dir/Screenshot_2026-10-22.png"
    screenshot_event "$dir/notes.txt"
    screenshot_event "$dir/.Screenshot.png.part"
    screenshot_event "$dir/foto liburan.JPG"
    screenshot_event "$dir/b.jpeg"
  } > "$RESULT"
  [ "$(jq -sc 'map([.kind,.text,.value,.level,.image])' "$RESULT")" = '[["screenshot","Tangkapan layar","Screenshot_2026-10-22.png",-1,"file:///home/user/Gambar/Screenshots/Screenshot_2026-10-22.png"],["screenshot","Tangkapan layar","foto liburan.JPG",-1,"file:///home/user/Gambar/Screenshots/foto%20liburan.JPG"],["screenshot","Tangkapan layar","b.jpeg",-1,"file:///home/user/Gambar/Screenshots/b.jpeg"]]' ]
  [ "$(jq -sr 'map(.icon)|join("|")' "$RESULT")" = $'\U000F0100|\U000F0100|\U000F0100' ]
}

@test "screenshot image is a file URI safe to embed in a CSS url" {
  screenshot_event "/home/user/Layar (1)/it's a\\shot.png" > "$RESULT"
  [ "$(jq -r .value "$RESULT")" = "it's a\\shot.png" ]
  [ "$(jq -r .image "$RESULT")" = 'file:///home/user/Layar%20%281%29/it%27s%20a%5Cshot.png' ]
}

@test "screenshot directory follows ob-screenshot: override, else XDG pictures (\$HOME when unset)" {
  export HOME="$BATS_TEST_TMPDIR/home"
  [ "$(screenshot_dir)" = "$ISLAND_SCREENSHOT_DIR" ]
  unset ISLAND_SCREENSHOT_DIR
  cat > "$BIN/xdg-user-dir" <<'EOF'
#!/usr/bin/env bash
[[ $* == PICTURES ]] || exit 2
cat "$ALERT_FIXTURE/xdg-pictures"
EOF
  chmod +x "$BIN/xdg-user-dir"
  printf '%s\n' "$HOME/Gambar" > "$ALERT_FIXTURE/xdg-pictures"
  [ "$(screenshot_dir)" = "$HOME/Gambar/Screenshots" ]
  printf '%s\n' "$HOME" > "$ALERT_FIXTURE/xdg-pictures"
  [ "$(screenshot_dir)" = "$HOME/Screenshots" ]
  rm "$BIN/xdg-user-dir"
  [ "$(PATH="$BIN" screenshot_dir)" = "$HOME/Screenshots" ]
}

set_temp() {
  printf '%s\n' "$2" > "$ISLAND_HWMON/$1_input"
}

@test "temperature warns once per crossing and re-arms only below threshold minus five" {
  make_hwmon hwmon0 'CPU Temperature:50000' 'GPU Temperature:50000'
  temperature_find
  {
    temperature_snapshot
    set_temp hwmon0/temp1 94999; temperature_snapshot
    set_temp hwmon0/temp1 95000; temperature_snapshot
    set_temp hwmon0/temp1 99000; temperature_snapshot
    set_temp hwmon0/temp1 90500; temperature_snapshot
    set_temp hwmon0/temp1 96000; temperature_snapshot
    set_temp hwmon0/temp1 89999; temperature_snapshot
    set_temp hwmon0/temp1 96400; temperature_snapshot
    set_temp hwmon0/temp2 86999; temperature_snapshot
    set_temp hwmon0/temp2 87000; temperature_snapshot
    temperature_snapshot
  } > "$RESULT"
  [ "$(jq -sc 'map([.kind,.text,.value,.level,.image])' "$RESULT")" = '[["temperature","CPU panas","95°C",-1,""],["temperature","CPU panas","96°C",-1,""],["temperature","GPU panas","87°C",-1,""]]' ]
  [ "$(jq -sr 'map(.icon)|join("|")' "$RESULT")" = $'\U000F050F|\U000F050F|\U000F050F' ]
}

@test "starting hot is silent until re-armed and thresholds follow the environment" {
  export ISLAND_TEMP_CPU=80 ISLAND_TEMP_GPU=70
  make_hwmon hwmon0 'CPU Temperature:85000' 'GPU Temperature:72000'
  temperature_find
  {
    temperature_snapshot
    temperature_snapshot
    set_temp hwmon0/temp1 75500; temperature_snapshot
    set_temp hwmon0/temp1 81000; temperature_snapshot
    set_temp hwmon0/temp1 74000; temperature_snapshot
    set_temp hwmon0/temp1 80000; temperature_snapshot
    set_temp hwmon0/temp2 64000; temperature_snapshot
    set_temp hwmon0/temp2 70000; temperature_snapshot
  } > "$RESULT"
  [ "$(jq -sc 'map([.text,.value])' "$RESULT")" = '[["CPU panas","80°C"],["GPU panas","70°C"]]' ]
}

@test "cpu sensor prefers CPU Temperature then Package id 0 then Tctl" {
  make_hwmon hwmon0 'Composite:40000'
  make_hwmon hwmon1 'Tctl:40000'
  make_hwmon hwmon2 'Package id 0:40000' 'Core 0:40000'
  make_hwmon hwmon3 'CPU Temperature:40000' 'GPU Temperature:40000'
  {
    (
      temperature_find; temperature_snapshot
      set_temp hwmon0/temp1 99000; set_temp hwmon1/temp1 99000
      set_temp hwmon2/temp1 99000; set_temp hwmon2/temp2 99000
      temperature_snapshot
      set_temp hwmon3/temp1 97000; temperature_snapshot
    )
    rm -r "$ISLAND_HWMON/hwmon3"
    set_temp hwmon1/temp1 40000; set_temp hwmon2/temp1 40000
    (
      temperature_find; temperature_snapshot
      set_temp hwmon1/temp1 99000; temperature_snapshot
      set_temp hwmon2/temp1 98000; temperature_snapshot
    )
    rm -r "$ISLAND_HWMON/hwmon2"
    set_temp hwmon1/temp1 40000
    (
      temperature_find; temperature_snapshot
      set_temp hwmon0/temp1 99000; temperature_snapshot
      set_temp hwmon1/temp1 96000; temperature_snapshot
    )
  } > "$RESULT"
  [ "$(jq -sc 'map([.text,.value])' "$RESULT")" = '[["CPU panas","97°C"],["CPU panas","98°C"],["CPU panas","96°C"]]' ]
}

set_led() {
  mkdir -p "$ISLAND_LEDS/$1"
  printf '%s\n' "$2" > "$ISLAND_LEDS/$1/brightness"
}

@test "caps lock is on when any keyboard LED is lit and emits only on change" {
  set_led input3::capslock 0
  set_led input7::capslock 0
  set_led input3::numlock 1
  {
    capslock_snapshot
    set_led input3::numlock 0; capslock_snapshot
    set_led input7::capslock 1; capslock_snapshot
    set_led input3::capslock 1; capslock_snapshot
    set_led input7::capslock 0; capslock_snapshot
    set_led input3::capslock 0; capslock_snapshot
    capslock_snapshot
  } > "$RESULT"
  [ "$(jq -sc 'map([.kind,.text,.value,.level,.image])' "$RESULT")" = '[["capslock","Caps Lock nyala","",-1,""],["capslock","Caps Lock mati","",-1,""]]' ]
  [ "$(jq -sr 'map(.icon)|join("|")' "$RESULT")" = $'\U000F0632|\U000F0632' ]
}

@test "caps lock already on at start is a silent baseline" {
  set_led input3::capslock 1
  {
    capslock_snapshot
    capslock_snapshot
    set_led input3::capslock 0; capslock_snapshot
  } > "$RESULT"
  [ "$(jq -sc 'map(.text)' "$RESULT")" = '["Caps Lock mati"]' ]
}

set_profile() {
  printf '%s\n' "$1" > "$ISLAND_PLATFORM_PROFILE"
}

@test "power profile changes emit the mode name with a per-mode icon after a silent baseline" {
  set_profile performance
  {
    power_snapshot
    power_snapshot
    set_profile low-power; power_snapshot
    set_profile balanced; power_snapshot
    power_snapshot
    set_profile performance; power_snapshot
    set_profile max-power; power_snapshot
    set_profile custom; power_snapshot
    set_profile quiet; power_snapshot
  } > "$RESULT"
  [ "$(jq -sc 'map([.kind,.text,.value,.level,.image])' "$RESULT")" = '[["power","Mode daya","Hemat daya",-1,""],["power","Mode daya","Seimbang",-1,""],["power","Mode daya","Performa",-1,""],["power","Mode daya","Daya maksimum",-1,""],["power","Mode daya","Kustom",-1,""],["power","Mode daya","quiet",-1,""]]' ]
  [ "$(jq -sr 'map(.icon)|join("|")' "$RESULT")" = $'\U000F032A|\U000F05D1|\U000F04C5|\U000F0463|\U000F062E|\U000F062E' ]
}

@test "power profile snapshot fails without emitting when the file is unreadable" {
  run power_snapshot
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "sources without their tools, sensors or LEDs are skipped with a note" {
  local source
  for source in bluetooth screenshot temperature capslock power; do
    run bash -c 'source "$2"; PATH=$1; source_worker "$3"' _ "$BIN" "$SCRIPTS/alert" "$source"
    [ "$status" -eq 0 ]
    case $source in
      bluetooth) [ "$output" = 'alert: sumber bluetooth dilewati, gdbus tidak tersedia' ] ;;
      screenshot) [ "$output" = 'alert: sumber screenshot dilewati, inotifywait tidak tersedia' ] ;;
      temperature) [ "$output" = 'alert: sumber temperature dilewati, sensor suhu tidak ditemukan' ] ;;
      capslock) [ "$output" = 'alert: sumber capslock dilewati, LED Caps Lock tidak ditemukan' ] ;;
      power) [ "$output" = 'alert: sumber power dilewati, platform_profile tidak ditemukan' ] ;;
    esac
  done
}

start_listener() {
  make_fakes
  export ISLAND_HUD_SECONDS=0.25 ISLAND_ALERT_SECONDS=0.4 ISLAND_CAPS_INTERVAL=0.02 ISLAND_TEMP_INTERVAL=0.05 ISLAND_POWER_INTERVAL=0.02
  mkfifo "$ALERT_FIXTURE/output"
  exec {output_fd}<> "$ALERT_FIXTURE/output"
  "$SCRIPTS/alert" > "$ALERT_FIXTURE/output" 2> "$ALERT_FIXTURE/stderr" &
  listener_pid=$!
  IFS= read -r -t 2 -u "$output_fd" first
  [ "$first" = "$CLEAR" ]
  for source in audio brightness battery wifi bluetooth screenshot; do
    for ((attempt=0; attempt<200; attempt++)); do
      [[ -e $ALERT_FIXTURE/$source-ready ]] && break
      sleep 0.005
    done
    [ -e "$ALERT_FIXTURE/$source-ready" ]
  done
  exec {audio_fd}<> "$ALERT_FIXTURE/audio-events"
  exec {brightness_fd}<> "$ALERT_FIXTURE/brightness-events"
  exec {battery_fd}<> "$ALERT_FIXTURE/battery-events"
  exec {wifi_fd}<> "$ALERT_FIXTURE/wifi-events"
  exec {bluetooth_fd}<> "$ALERT_FIXTURE/bluetooth-events"
  exec {screenshot_fd}<> "$ALERT_FIXTURE/screenshot-events"
  # Pollers take their baseline at worker start; give them a moment before changing inputs.
  sleep 0.1
}

@test "listener starts cleared then emits a changed volume and clears after its hold" {
  start_listener
  ! IFS= read -r -t 0.04 -u "$output_fd" event
  printf '55\n' > "$ALERT_FIXTURE/volume"
  printf "Event 'change' on sink #65\n" >&"$audio_fd"
  IFS= read -r -t 1 -u "$output_fd" event
  [ "$(jq -c '[.kind,.value,.level]' <<< "$event")" = '["volume","55%",55]' ]
  IFS= read -r -t 1 -u "$output_fd" event
  [ "$event" = "$CLEAR" ]
  ! IFS= read -r -t 0.04 -u "$output_fd" event
}

@test "a newer alert immediately replaces a HUD and receives the longer alert hold" {
  start_listener
  printf '55\n' > "$ALERT_FIXTURE/volume"
  printf "Event 'change' on server\n" >&"$audio_fd"
  IFS= read -r -t 1 -u "$output_fd" event
  [ "$(jq -r .kind <<< "$event")" = volume ]
  printf 'wlan0: connected\n' >&"$wifi_fd"
  IFS= read -r -t 1 -u "$output_fd" event
  [ "$(jq -r .kind <<< "$event")" = wifi ]
  ! IFS= read -r -t 0.29 -u "$output_fd" event
  IFS= read -r -t 1 -u "$output_fd" event
  [ "$event" = "$CLEAR" ]
}

@test "repeated identical volume events extend the HUD without duplicate JSON" {
  start_listener
  printf '55\n' > "$ALERT_FIXTURE/volume"
  printf "Event 'change' on sink #65\n" >&"$audio_fd"
  IFS= read -r -t 1 -u "$output_fd" event
  [ "$(jq -r .kind <<< "$event")" = volume ]
  sleep 0.15
  printf "Event 'change' on sink #65\n" >&"$audio_fd"
  ! IFS= read -r -t 0.15 -u "$output_fd" event
  IFS= read -r -t 1 -u "$output_fd" event
  [ "$event" = "$CLEAR" ]
}

@test "listener holds an audio output switch for the alert hold" {
  start_listener
  write_sinks bluez_output.F4_93_B1_9A_5C_21.1
  printf "Event 'change' on server\n" >&"$audio_fd"
  IFS= read -r -t 1 -u "$output_fd" event
  [ "$(jq -c '[.kind,.text,.value,.level]' <<< "$event")" = '["output","Output audio","WH-1000XM4",-1]' ]
  ! IFS= read -r -t 0.29 -u "$output_fd" event
  IFS= read -r -t 1 -u "$output_fd" event
  [ "$event" = "$CLEAR" ]
}

@test "caps lock toggles show a HUD that clears after the shorter HUD hold" {
  start_listener
  printf '1\n' > "$ISLAND_LEDS/input3::capslock/brightness"
  IFS= read -r -t 1 -u "$output_fd" event
  [ "$(jq -c '[.kind,.text,.level]' <<< "$event")" = '["capslock","Caps Lock nyala",-1]' ]
  IFS= read -r -t 0.35 -u "$output_fd" event
  [ "$event" = "$CLEAR" ]
}

@test "power profile changes reach the listener with the alert hold" {
  start_listener
  ! IFS= read -r -t 0.1 -u "$output_fd" event
  printf 'balanced\n' > "$ISLAND_PLATFORM_PROFILE"
  IFS= read -r -t 1 -u "$output_fd" event
  [ "$(jq -c '[.kind,.text,.value,.level]' <<< "$event")" = '["power","Mode daya","Seimbang",-1]' ]
  ! IFS= read -r -t 0.29 -u "$output_fd" event
  IFS= read -r -t 1 -u "$output_fd" event
  [ "$event" = "$CLEAR" ]
}

@test "listener forwards temperature bluetooth and screenshot alerts with the alert hold" {
  start_listener
  ! IFS= read -r -t 0.1 -u "$output_fd" event
  printf '96000\n' > "$ISLAND_HWMON/hwmon3/temp1_input"
  IFS= read -r -t 1 -u "$output_fd" event
  [ "$(jq -c '[.kind,.text,.value]' <<< "$event")" = '["temperature","CPU panas","96°C"]' ]
  bt_line F4_93_B1_9A_5C_21 Device1 "'Connected': <true>" >&"$bluetooth_fd"
  printf '\n' >&"$bluetooth_fd"
  IFS= read -r -t 1 -u "$output_fd" event
  [ "$(jq -c '[.kind,.text,.value]' <<< "$event")" = '["bluetooth","Bluetooth tersambung","WH-1000XM4 · 80%"]' ]
  printf '%s\n' "$ISLAND_SCREENSHOT_DIR/shot.png" >&"$screenshot_fd"
  IFS= read -r -t 1 -u "$output_fd" event
  [ "$(jq -c '[.kind,.value,.image]' <<< "$event")" = "$(jq -cn --arg d "$ISLAND_SCREENSHOT_DIR" '["screenshot","shot.png","file://\($d)/shot.png"]')" ]
  ! IFS= read -r -t 0.29 -u "$output_fd" event
  IFS= read -r -t 1 -u "$output_fd" event
  [ "$event" = "$CLEAR" ]
}
