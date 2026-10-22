# tests/weather/common.bash: shared fixture, fake tools and listener helpers of the weather tests
load ../helpers

setup() {
  export WEATHER_FIXTURE="$BATS_TEST_TMPDIR"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  export HOME="$BATS_TEST_TMPDIR/home"
  export ISLAND_WEATHER_INTERVAL=1800 ISLAND_WEATHER_RETRY=300
  export TZ=UTC LC_ALL=C
  export REAL_DATE
  REAL_DATE=$(command -v date)
  export ISLAND_GEOCLUE_WHEREAMI="$BATS_TEST_TMPDIR/bin/where-am-i"
  ORIGINAL_PATH=$PATH
  BIN="$BATS_TEST_TMPDIR/bin"
  CFG="$BATS_TEST_TMPDIR/eww"
  mkdir -p "$BIN" "$CFG/scripts" "$XDG_CACHE_HOME/eww-island" "$HOME"
  local tool
  for tool in bash cat chmod dirname jq mkdir mktemp mv rm tr; do
    ln -s "$(command -v "$tool")" "$BIN/$tool"
  done
  SETSID=$(command -v setsid)
  cp -r "$SCRIPTS/lib" "$CFG/scripts/lib"
  if [[ -f $SCRIPTS/weather ]]; then cp "$SCRIPTS/weather" "$CFG/scripts/weather"; fi
  printf '100000\n' > "$WEATHER_FIXTURE/epoch"
  printf '12\n' > "$WEATHER_FIXTURE/hour"
  printf '0\n' > "$WEATHER_FIXTURE/calls"
  printf '0\n' > "$WEATHER_FIXTURE/curl-status"
  printf '{"current_condition":[{"temp_C":"29","weatherCode":"113"}]}\n' > "$WEATHER_FIXTURE/response"
  printf '{}\n' > "$WEATHER_FIXTURE/geocode-response"
  printf '22\n' > "$WEATHER_FIXTURE/geocode-status"
  printf '1\n' > "$WEATHER_FIXTURE/geoclue-status"
  printf '' > "$WEATHER_FIXTURE/geoclue-response"
  mkfifo "$WEATHER_FIXTURE/output" "$WEATHER_FIXTURE/ticks" \
    "$WEATHER_FIXTURE/sleeps" "$WEATHER_FIXTURE/fetch-gate"
  exec {output_fd}<> "$WEATHER_FIXTURE/output"
  exec {tick_fd}<> "$WEATHER_FIXTURE/ticks"
  exec {sleep_fd}<> "$WEATHER_FIXTURE/sleeps"
  exec {gate_fd}<> "$WEATHER_FIXTURE/fetch-gate"
  cat > "$BIN/date" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  +%s) cat "$WEATHER_FIXTURE/epoch" ;;
  +%H) cat "$WEATHER_FIXTURE/hour" ;;
  *) "$REAL_DATE" "$@" ;;
esac
EOF
  cat > "$BIN/sleep" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" > "$WEATHER_FIXTURE/sleeps"
IFS= read -r _ < "$WEATHER_FIXTURE/ticks"
EOF
  cat > "$BIN/curl" <<'EOF'
#!/usr/bin/env bash
[[ $1 == -sf && $2 == --max-time && $3 == 8 ]] || exit 2
if [[ $# == 6 && $4 == -H &&
      $5 == 'User-Agent: openbox-island/1.0 (+https://github.com/ardzz/openbox-island)' &&
      $6 == https://nominatim.openstreetmap.org/reverse* ]]; then
  printf '%s\n' "$6" >> "$WEATHER_FIXTURE/geocode-urls"
  read -r status < "$WEATHER_FIXTURE/geocode-status"
  (( status == 0 )) || exit "$status"
  cat "$WEATHER_FIXTURE/geocode-response"
  exit
fi
[[ $# == 4 && $4 == https://wttr.in/* ]] || exit 2
printf '%s\n' "$4" >> "$WEATHER_FIXTURE/urls"
read -r calls < "$WEATHER_FIXTURE/calls"
printf '%s\n' "$((calls + 1))" > "$WEATHER_FIXTURE/calls"
if [[ -f $WEATHER_FIXTURE/block-fetch ]]; then
  IFS= read -r _ < "$WEATHER_FIXTURE/fetch-gate"
fi
read -r status < "$WEATHER_FIXTURE/curl-status"
(( status == 0 )) || exit "$status"
cat "$WEATHER_FIXTURE/response"
EOF
  cat > "$BIN/timeout" <<'EOF'
#!/usr/bin/env bash
[[ $# == 4 && $1 == 15 && $2 == "$ISLAND_GEOCLUE_WHEREAMI" && $3 == -t && $4 == 10 ]] || exit 2
shift
exec "$@"
EOF
  cat > "$BIN/where-am-i" <<'EOF'
#!/usr/bin/env bash
printf 'called\n' >> "$WEATHER_FIXTURE/geoclue-calls"
cat "$WEATHER_FIXTURE/geoclue-response"
read -r status < "$WEATHER_FIXTURE/geoclue-status"
exit "$status"
EOF
  cat > "$BIN/stat" <<'EOF'
#!/usr/bin/env bash
[[ $# == 3 && $1 == -c && $2 == %Y && -f $3 ]] || exit 2
printf '100000\n'
EOF
  chmod +x "$BIN/date" "$BIN/sleep" "$BIN/curl" "$BIN/timeout" "$BIN/where-am-i" "$BIN/stat"
  export PATH="$BIN"
  EMPTY='{"ok":false,"icon":"","tone":"","temp":"","desc":"","city":"","region":"","feels":"","humidity":"","wind":"","uv":"","sunrise":"","sunset":"","days":[]}'
}

teardown() {
  export PATH="$ORIGINAL_PATH"
  if [[ -n ${listener_pid:-} ]]; then
    kill -TERM -- "-$listener_pid" 2>/dev/null || :
    wait "$listener_pid" 2>/dev/null || :
  fi
  exec {output_fd}>&-
  exec {tick_fd}>&-
  exec {sleep_fd}>&-
  exec {gate_fd}>&-
}

start_weather() {
  [ -x "$SCRIPTS/weather" ]
  "$SETSID" "$CFG/scripts/weather" > "$WEATHER_FIXTURE/output" 2> "$WEATHER_FIXTURE/stderr" &
  listener_pid=$!
  next_weather
}

next_weather() {
  IFS= read -r -t 2 -u "$output_fd" event
}

assert_weather() {
  local temp=$1 desc=$2 icon=$3
  # tone has its own tests; compare the rest of the event exactly.
  [ "$(jq -c 'del(.tone)' <<< "$event")" = "{\"ok\":true,\"icon\":\"$icon\",\"temp\":\"$temp\",\"desc\":\"$desc\",\"city\":\"\",\"region\":\"\",\"feels\":\"\",\"humidity\":\"\",\"wind\":\"\",\"uv\":\"\",\"sunrise\":\"\",\"sunset\":\"\",\"days\":[]}" ]
}

weather_tick() {
  local epoch=$1 hour=${2:-12}
  IFS= read -r -t 2 -u "$sleep_fd" sleep_seconds
  [[ $sleep_seconds =~ ^[0-9]+$ ]]
  (( sleep_seconds > 0 && sleep_seconds <= 60 ))
  printf '%s\n' "$epoch" > "$WEATHER_FIXTURE/epoch"
  printf '%s\n' "$hour" > "$WEATHER_FIXTURE/hour"
  printf 'tick\n' >&"$tick_fd"
}

seed_weather_cache() {
  printf '{"current_condition":[{"temp_C":"21","weatherCode":"113"}]}\n' > "$WEATHER_FIXTURE/response"
  start_weather
  IFS= read -r -t 2 -u "$sleep_fd" sleep_seconds
  stop_weather
  jq --argjson fetched "$1" '.fetched=$fetched' \
    "$XDG_CACHE_HOME/eww-island/weather.json" > "$WEATHER_FIXTURE/seed"
  mv "$WEATHER_FIXTURE/seed" "$XDG_CACHE_HOME/eww-island/weather.json"
  printf '{"current_condition":[{"temp_C":"29","weatherCode":"113"}]}\n' > "$WEATHER_FIXTURE/response"
  printf '0\n' > "$WEATHER_FIXTURE/calls"
  printf '' > "$WEATHER_FIXTURE/urls"
}

stop_weather() {
  kill -TERM -- "-$listener_pid" 2>/dev/null || :
  wait "$listener_pid" 2>/dev/null || :
  listener_pid=''
}

realistic_weather() {
  cat > "$WEATHER_FIXTURE/response" <<'EOF'
{"current_condition":[{"temp_C":"28","FeelsLikeC":"30","humidity":"68","uvIndex":"0","windspeedKmph":"4","weatherCode":"149"}],"nearest_area":[{"areaName":[{"value":"Alun-Aluncontong"}],"region":[{"value":"East Java"}],"latitude":"-7.25","longitude":"112.75"}],"weather":[{"date":"2026-10-22","maxtempC":"35","mintempC":"26","astronomy":[{"sunrise":"05:05 AM","sunset":"05:23 PM"}],"hourly":[{"time":"0","weatherCode":"113","chanceofrain":"7"},{"time":"1200","weatherCode":"149","chanceofrain":"2"}]},{"date":"2026-10-23","maxtempC":"34","mintempC":"25","astronomy":[{"sunrise":"05:04 AM","sunset":"05:24 PM"}],"hourly":[{"time":"0","weatherCode":"113","chanceofrain":"9"},{"time":"1200","weatherCode":"302","chanceofrain":"80"}]},{"date":"2026-10-24","maxtempC":"33","mintempC":"24","hourly":[{"time":"300","weatherCode":"116","chanceofrain":"10"},{"time":"1800","weatherCode":"302","chanceofrain":"6"}]}]}
EOF
}

change_response() {
  jq "$1" "$WEATHER_FIXTURE/response" > "$WEATHER_FIXTURE/changed"
  mv "$WEATHER_FIXTURE/changed" "$WEATHER_FIXTURE/response"
}

assert_fields() {
  run jq -ce "$1" <<< "$event"
  [ "$status" -eq 0 ]
}

enable_geoclue() {
  printf '0\n' > "$WEATHER_FIXTURE/geoclue-status"
  printf 'Latitude: 1.0°\nLongitude: 2.0°\nLatitude:    -7.257472°\nLongitude:    112.752090°\n' \
    > "$WEATHER_FIXTURE/geoclue-response"
}

enable_geocode() {
  printf '0\n' > "$WEATHER_FIXTURE/geocode-status"
  printf '{"address":{"city":"Surabaya","state":"Jawa Timur"}}\n' > "$WEATHER_FIXTURE/geocode-response"
}
