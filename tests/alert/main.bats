# tests/alert/main.bats
load helpers

start_listener() {
  make_fakes
  export ISLAND_HUD_SECONDS=0.25 ISLAND_ALERT_SECONDS=0.4 ISLAND_CAPS_INTERVAL=0.02 ISLAND_TEMP_INTERVAL=0.05 ISLAND_POWER_INTERVAL=0.02 ISLAND_CONSERVATION_INTERVAL=0.02
  export ISLAND_VPN_INTERVAL=0.05
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

@test "initial audio, brightness, and battery samples produce no alert" {
  {
    audio_update 42 no no
    brightness_update 17.00
    battery_update discharging 76
  } > "$RESULT"
  [ ! -s "$RESULT" ]
}

@test "each monitor connection silently refreshes its baseline before queued events" {
  make_fakes
  make_queued_monitor
  battery_path=/org/freedesktop/UPower/devices/battery_BAT1
  {
    alert_source=audio source_stream queued_monitor "Event 'change' on server"
    alert_source=brightness source_stream queued_monitor 'UDEV backlight'
    alert_source=battery source_stream queued_monitor "device changed: $battery_path"
    alert_source=wifi source_stream queued_monitor 'wlan0: disconnected'
  } > "$RESULT"
  [ ! -s "$RESULT" ]
  printf '55\n' > "$ALERT_FIXTURE/volume"
  printf 'yes\n' > "$ALERT_FIXTURE/mic"
  printf '34.5\n' > "$ALERT_FIXTURE/brightness"
  printf '19\n' > "$ALERT_FIXTURE/battery-percent"
  printf 'charging\n' > "$ALERT_FIXTURE/battery-state"
  wifi_event 'wlan0: connected' > /dev/null
  {
    alert_source=audio source_stream queued_monitor "Event 'change' on server"
    alert_source=brightness source_stream queued_monitor 'UDEV backlight'
    alert_source=battery source_stream queued_monitor "device changed: $battery_path"
    alert_source=wifi source_stream queued_monitor 'wlan0: disconnected'
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

@test "sources without their tools, sensors, LEDs or files are skipped with a note" {
  local source
  for source in bluetooth screenshot temperature capslock power conservation; do
    run bash -c 'source "$2"; PATH=$1; alert_source=$3; source_worker' _ "$BIN" "$SCRIPTS/alert" "$source"
    [ "$status" -eq 0 ]
    case $source in
      bluetooth) [ "$output" = 'alert: sumber bluetooth dilewati, gdbus tidak tersedia' ] ;;
      screenshot) [ "$output" = 'alert: sumber screenshot dilewati, inotifywait tidak tersedia' ] ;;
      temperature) [ "$output" = 'alert: sumber temperature dilewati, sensor suhu tidak ditemukan' ] ;;
      capslock) [ "$output" = 'alert: sumber capslock dilewati, LED Caps Lock tidak ditemukan' ] ;;
      power) [ "$output" = 'alert: sumber power dilewati, platform_profile tidak ditemukan' ] ;;
      conservation) [ "$output" = 'alert: sumber conservation dilewati, conservation_mode tidak ditemukan' ] ;;
    esac
  done
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

@test "listener forwards conservation toggles and the limited charging value" {
  start_listener
  ! IFS= read -r -t 0.1 -u "$output_fd" event
  printf '1\n' > "$ISLAND_CONSERVATION"
  IFS= read -r -t 1 -u "$output_fd" event
  [ "$(jq -c '[.kind,.text,.value,.level]' <<< "$event")" = '["battery","Batas pengisian aktif","80%",-1]' ]
  printf 'charging\n' > "$ALERT_FIXTURE/battery-state"
  printf 'device changed: /org/freedesktop/UPower/devices/battery_BAT1\n' >&"$battery_fd"
  IFS= read -r -t 1 -u "$output_fd" event
  [ "$(jq -c '[.kind,.text,.value,.level]' <<< "$event")" = '["charging","Mengisi daya","76% · batas 80%",76]' ]
}

@test "listener forwards vpn alerts from its poller" {
  start_listener
  ! IFS= read -r -t 0.1 -u "$output_fd" event
  make_iface tekna0 tun
  IFS= read -r -t 1 -u "$output_fd" event
  [ "$(jq -c '[.kind,.text,.value]' <<< "$event")" = '["vpn","VPN tersambung","tekna0"]' ]
  ts_set NeedsLogin
  IFS= read -r -t 1 -u "$output_fd" event
  [ "$(jq -c '[.kind,.text]' <<< "$event")" = '["vpn-error","Tailscale perlu login"]' ]
}

@test "listener tells the notification listener when an alert run starts and when it clears" {
  mkdir -p "$XDG_RUNTIME_DIR/eww-island"
  mkfifo "$XDG_RUNTIME_DIR/eww-island/notify.fifo"
  exec {notify_fd}<> "$XDG_RUNTIME_DIR/eww-island/notify.fifo"
  start_listener
  printf '55\n' > "$ALERT_FIXTURE/volume"
  printf "Event 'change' on sink #65\n" >&"$audio_fd"
  IFS= read -r -t 1 -u "$output_fd" event
  [ "$(jq -r .kind <<< "$event")" = volume ]
  IFS= read -r -t 1 -u "$notify_fd" signal
  [ "$signal" = '@alert 1' ]
  printf 'wlan0: connected\n' >&"$wifi_fd"
  IFS= read -r -t 1 -u "$output_fd" event
  [ "$(jq -r .kind <<< "$event")" = wifi ]
  IFS= read -r -t 1 -u "$output_fd" event
  [ "$event" = "$CLEAR" ]
  IFS= read -r -t 1 -u "$notify_fd" signal
  [ "$signal" = '@alert 0' ]
  if IFS= read -r -t 0.1 -u "$notify_fd" signal; then false; fi
}
