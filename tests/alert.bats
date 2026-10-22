load helpers

setup() {
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export ALERT_FIXTURE="$BATS_TEST_TMPDIR"
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN" "$XDG_RUNTIME_DIR"
  export PATH="$BIN:$PATH"
  source "$SCRIPTS/alert"
  CLEAR='{"kind":"","icon":"","text":"","value":"","level":-1}'
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
  mkfifo "$ALERT_FIXTURE/audio-events" "$ALERT_FIXTURE/brightness-events" \
    "$ALERT_FIXTURE/battery-events" "$ALERT_FIXTURE/wifi-events"
  cat > "$BIN/pactl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$ALERT_FIXTURE/audio-queries"
case $1 in
  subscribe) touch "$ALERT_FIXTURE/audio-ready"; exec cat "$ALERT_FIXTURE/audio-events" ;;
  get-sink-volume) read -r n < "$ALERT_FIXTURE/volume"; printf 'Volume: front-left: 27525 / %s%% / -23 dB, front-right: 65536 / 100%% / 0 dB\n' "$n" ;;
  get-sink-mute) printf 'Mute: '; cat "$ALERT_FIXTURE/mute" ;;
  get-source-mute) printf 'Mute: '; cat "$ALERT_FIXTURE/mic" ;;
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
  chmod +x "$BIN/pactl" "$BIN/light" "$BIN/udevadm" "$BIN/upower" "$BIN/nmcli"
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

start_listener() {
  make_fakes
  export ISLAND_HUD_SECONDS=0.25 ISLAND_ALERT_SECONDS=0.4
  mkfifo "$ALERT_FIXTURE/output"
  exec {output_fd}<> "$ALERT_FIXTURE/output"
  "$SCRIPTS/alert" > "$ALERT_FIXTURE/output" 2> "$ALERT_FIXTURE/stderr" &
  listener_pid=$!
  IFS= read -r -t 2 -u "$output_fd" first
  [ "$first" = "$CLEAR" ]
  for source in audio brightness battery wifi; do
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
