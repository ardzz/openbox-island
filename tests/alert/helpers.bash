# tests/alert/helpers.bash: environment and fake tools shared by the alert tests.
load ../helpers

setup() {
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run" XDG_DATA_HOME="$BATS_TEST_TMPDIR/data" ISLAND_CALENDARS="$BATS_TEST_TMPDIR/calendars"
  export ALERT_FIXTURE="$BATS_TEST_TMPDIR"
  export ISLAND_HWMON="$BATS_TEST_TMPDIR/hwmon" ISLAND_LEDS="$BATS_TEST_TMPDIR/leds"
  export ISLAND_SYSNET="$BATS_TEST_TMPDIR/net"
  export ISLAND_SCREENSHOT_DIR="$BATS_TEST_TMPDIR/shots" ISLAND_CONSERVATION="$BATS_TEST_TMPDIR/conservation_mode"
  export ISLAND_PLATFORM_PROFILE="$BATS_TEST_TMPDIR/platform_profile"
  unset ISLAND_TEMP_CPU ISLAND_TEMP_GPU
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN" "$XDG_RUNTIME_DIR" "$ISLAND_HWMON" "$ISLAND_LEDS" "$ISLAND_SYSNET"
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

make_fakes() {
  printf '42\n' > "$ALERT_FIXTURE/volume"
  printf 'no\n' > "$ALERT_FIXTURE/mute"
  printf 'no\n' > "$ALERT_FIXTURE/mic"
  printf '17.00\n' > "$ALERT_FIXTURE/brightness"
  printf 'discharging\n' > "$ALERT_FIXTURE/battery-state"
  printf '76\n' > "$ALERT_FIXTURE/battery-percent"
  write_sinks alsa_output.pci-0000_00_1f.3.analog-stereo
  printf '0\n' > "$ISLAND_CONSERVATION"
  mkfifo "$ALERT_FIXTURE/audio-events" "$ALERT_FIXTURE/brightness-events" \
    "$ALERT_FIXTURE/battery-events" "$ALERT_FIXTURE/wifi-events" \
    "$ALERT_FIXTURE/bluetooth-events" "$ALERT_FIXTURE/screenshot-events"
  printf 'Device AA:BB:CC:DD:EE:01 Keyboard K380\n' > "$ALERT_FIXTURE/bt-connected"
  printf 'Device AA:BB:CC:DD:EE:01 (public)\n\tName: K380\n\tAlias: Keyboard K380\n\tIcon: input-keyboard\n\tConnected: yes\n' \
    > "$ALERT_FIXTURE/bt-info-AA:BB:CC:DD:EE:01"
  printf 'Device F4:93:B1:9A:5C:21 (public)\n\tName: WH-1000XM4\n\tAlias: WH-1000XM4\n\tClass: 0x00240404\n\tIcon: audio-headset\n\tConnected: yes\n\tBattery Percentage: 0x50 (80)\n' \
    > "$ALERT_FIXTURE/bt-info-F4:93:B1:9A:5C:21"
  make_hwmon hwmon3 'CPU Temperature:50000' 'GPU Temperature:50000'
  make_tailscale
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

# make_queued_monitor: a monitor command printing its argument as one event, then exiting.
make_queued_monitor() {
  cat > "$BIN/queued_monitor" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1"
sleep 0.05
EOF
  chmod +x "$BIN/queued_monitor"
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

bt_line() {
  printf "/org/bluez/hci0/dev_%s: org.freedesktop.DBus.Properties.PropertiesChanged ('org.bluez.%s', {%s}, @as [])" "$1" "$2" "$3"
}

# make_iface NAME tun|tap|wireguard|plain [OPERSTATE]: one fake /sys/class/net entry.
make_iface() {
  local dir="$ISLAND_SYSNET/$1"
  mkdir -p "$dir"
  printf 'INTERFACE=%s\nIFINDEX=7\n' "$1" > "$dir/uevent"
  case $2 in
    tun) printf '0x5001\n' > "$dir/tun_flags" ;;
    tap) printf '0x5002\n' > "$dir/tun_flags" ;;
    wireguard) printf 'DEVTYPE=wireguard\nINTERFACE=%s\nIFINDEX=7\n' "$1" > "$dir/uevent" ;;
  esac
  printf '%s\n' "${3:-unknown}" > "$dir/operstate"
}

make_tailscale() {
  cat > "$BIN/tailscale" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$ALERT_FIXTURE/ts-calls"
[[ ! -e $ALERT_FIXTURE/ts-down ]] || { printf 'failed to connect to local tailscaled\n' >&2; exit 1; }
case "$*" in
  'status --json --peers=false') cat "$ALERT_FIXTURE/ts-self" ;;
  'status --json') cat "$ALERT_FIXTURE/ts-peers" ;;
  *) exit 2 ;;
esac
EOF
  chmod +x "$BIN/tailscale"
  ts_set Stopped
  ts_peers
}

# ts_set STATE [EXIT_ID EXIT_IP]: the --peers=false answer.
ts_set() {
  jq -cn --arg s "$1" --arg id "${2:-}" --arg ip "${3:-}" \
    '{BackendState:$s,Self:{HostName:"loq-irx10"},
      ExitNodeStatus:(if $id == "" then null else {ID:$id,Online:true,TailscaleIPs:[$ip + "/32"]} end)}' \
    > "$ALERT_FIXTURE/ts-self"
}

# ts_peers [EXIT_HOST]: the full answer; without a host no peer is the exit node.
ts_peers() {
  jq -cn --arg h "${1:-}" \
    '{BackendState:"Running",Peer:{"k1":{HostName:"laptop",ExitNode:false},
      "k2":{HostName:(if $h == "" then "server" else $h end),ExitNode:($h != "")}}}' \
    > "$ALERT_FIXTURE/ts-peers"
}
