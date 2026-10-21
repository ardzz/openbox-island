load helpers

setup() {
  export WEATHER_FIXTURE="$BATS_TEST_TMPDIR"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  export HOME="$BATS_TEST_TMPDIR/home"
  export ISLAND_WEATHER_INTERVAL=1800 ISLAND_WEATHER_RETRY=300
  ORIGINAL_PATH=$PATH
  BIN="$BATS_TEST_TMPDIR/bin"
  CFG="$BATS_TEST_TMPDIR/eww"
  mkdir -p "$BIN" "$CFG/scripts" "$XDG_CACHE_HOME/eww-island" "$HOME"
  local tool
  for tool in bash cat chmod dirname jq mkdir mktemp mv rm tr; do
    ln -s "$(command -v "$tool")" "$BIN/$tool"
  done
  SETSID=$(command -v setsid)
  cp "$SCRIPTS/lib.sh" "$CFG/scripts/lib.sh"
  if [[ -f $SCRIPTS/weather ]]; then cp "$SCRIPTS/weather" "$CFG/scripts/weather"; fi
  printf '100000\n' > "$WEATHER_FIXTURE/epoch"
  printf '12\n' > "$WEATHER_FIXTURE/hour"
  printf '0\n' > "$WEATHER_FIXTURE/calls"
  printf '0\n' > "$WEATHER_FIXTURE/curl-status"
  printf '{"current_condition":[{"temp_C":"29","weatherCode":"113"}]}\n' > "$WEATHER_FIXTURE/response"
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
  *) exit 2 ;;
esac
EOF
  cat > "$BIN/sleep" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" > "$WEATHER_FIXTURE/sleeps"
IFS= read -r _ < "$WEATHER_FIXTURE/ticks"
EOF
  cat > "$BIN/curl" <<'EOF'
#!/usr/bin/env bash
[[ $# == 4 && $1 == -sf && $2 == --max-time && $3 == 8 && $4 == https://wttr.in/* ]] || exit 2
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
  chmod +x "$BIN/date" "$BIN/sleep" "$BIN/curl"
  export PATH="$BIN"
  EMPTY='{"ok":false,"icon":"","temp":"","desc":""}'
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
  [ "$event" = "{\"ok\":true,\"icon\":\"$icon\",\"temp\":\"$temp\",\"desc\":\"$desc\"}" ]
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
  printf '{"temp_C":"21","weatherCode":"113","fetched":%s}\n' "$1" \
    > "$XDG_CACHE_HOME/eww-island/weather.json"
}

@test "weather maps representative WWO groups and unknown codes to Indonesian descriptions" {
  source "$SCRIPTS/weather"
  local code desc icon
  while IFS='|' read -r code desc icon; do
    run weather_json 29 "$code" 12
    [ "$status" -eq 0 ]
    event=$output
    assert_weather '29°' "$desc" "$icon"
  done <<'EOF'
113|Cerah|󰖙
116|Cerah berawan|󰖕
119|Berawan|󰖐
122|Berawan|󰖐
143|Berkabut|󰖑
248|Berkabut|󰖑
260|Berkabut|󰖑
176|Hujan ringan|󰖗
314|Hujan ringan|󰖗
353|Hujan ringan|󰖗
299|Hujan lebat|󰖖
359|Hujan lebat|󰖖
200|Badai petir|󰖓
395|Badai petir|󰖓
179|Salju|󰖘
377|Salju|󰖘
999|Berawan|󰖐
EOF
}

@test "clear weather changes glyph at local 06 and 18 boundaries" {
  source "$SCRIPTS/weather"
  local hour icon
  while IFS='|' read -r hour icon; do
    run weather_json 29 113 "$hour"
    [ "$status" -eq 0 ]
    event=$output
    assert_weather '29°' 'Cerah' "$icon"
  done <<'EOF'
5|󰖔
6|󰖙
17|󰖙
18|󰖔
23|󰖔
EOF
}

@test "weather formats zero and negative Celsius temperatures" {
  source "$SCRIPTS/weather"
  run weather_json 0 119 08
  [ "$status" -eq 0 ]
  event=$output
  assert_weather '0°' 'Berawan' '󰖐'
  run weather_json -7 119 09
  [ "$status" -eq 0 ]
  event=$output
  assert_weather '-7°' 'Berawan' '󰖐'
}

@test "invalid JSON and missing or invalid weather fields produce unavailable" {
  local response
  for response in 'not json' '{}' '{"current_condition":[]}' \
    '{"current_condition":[{"temp_C":"29"}]}' \
    '{"current_condition":[{"weatherCode":"113"}]}' \
    '{"current_condition":[{"temp_C":null,"weatherCode":"113"}]}' \
    '{"current_condition":[{"temp_C":"warm","weatherCode":"113"}]}' \
    '{"current_condition":[{"temp_C":"29","weatherCode":"sunny"}]}'; do
    printf '%s\n' "$response" > "$WEATHER_FIXTURE/response"
    start_weather
    [ "$event" = "$EMPTY" ]
    kill -TERM -- "-$listener_pid"
    wait "$listener_pid" 2>/dev/null || :
    listener_pid=''
  done
}

@test "location is trimmed and spaces are percent encoded in the fetch URL" {
  printf ' \tJakarta Selatan \n' > "$CFG/weather-location"
  start_weather
  assert_weather '29°' 'Cerah' '󰖙'
  run cat "$WEATHER_FIXTURE/urls"
  [ "$output" = 'https://wttr.in/Jakarta%20Selatan?format=j1' ]
}

@test "empty location uses wttr IP geolocation" {
  printf ' \t\n' > "$CFG/weather-location"
  start_weather
  assert_weather '29°' 'Cerah' '󰖙'
  run cat "$WEATHER_FIXTURE/urls"
  [ "$output" = 'https://wttr.in/?format=j1' ]
}

@test "missing location uses wttr IP geolocation and successful raw values are cached" {
  start_weather
  assert_weather '29°' 'Cerah' '󰖙'
  run cat "$WEATHER_FIXTURE/urls"
  [ "$output" = 'https://wttr.in/?format=j1' ]
  run jq -ce '{temp_C,weatherCode,fetched}' "$XDG_CACHE_HOME/eww-island/weather.json"
  [ "$status" -eq 0 ]
  [ "$output" = '{"temp_C":"29","weatherCode":"113","fetched":100000}' ]
}

@test "fresh cache emits before blocked fetch and recomputes current night glyph" {
  seed_weather_cache 99900
  printf '23\n' > "$WEATHER_FIXTURE/hour"
  printf '' > "$WEATHER_FIXTURE/block-fetch"
  start_weather
  assert_weather '21°' 'Cerah' '󰖔'
  printf 'continue\n' >&"$gate_fd"
  next_weather
  assert_weather '29°' 'Cerah' '󰖔'
}

@test "cache at three hours with failed fetch is unavailable" {
  seed_weather_cache 89200
  printf '22\n' > "$WEATHER_FIXTURE/curl-status"
  start_weather
  [ "$event" = "$EMPTY" ]
}

@test "failed fetch retains fresh cache without consecutive duplicate output" {
  seed_weather_cache 99900
  printf '22\n' > "$WEATHER_FIXTURE/curl-status"
  start_weather
  assert_weather '21°' 'Cerah' '󰖙'
  weather_tick 100060
  ! IFS= read -r -t 0.1 -u "$output_fd" event
}

@test "cached weather expires between fetches without waiting for retry" {
  seed_weather_cache 89201
  printf '22\n' > "$WEATHER_FIXTURE/curl-status"
  start_weather
  assert_weather '21°' 'Cerah' '󰖙'
  weather_tick 100001
  next_weather
  [ "$event" = "$EMPTY" ]
}

@test "clear glyph refreshes at day and night boundaries without a fetch" {
  printf '05\n' > "$WEATHER_FIXTURE/hour"
  start_weather
  assert_weather '29°' 'Cerah' '󰖔'
  weather_tick 100060 06
  next_weather
  assert_weather '29°' 'Cerah' '󰖙'
  weather_tick 100120 18
  next_weather
  assert_weather '29°' 'Cerah' '󰖔'
  run cat "$WEATHER_FIXTURE/calls"
  [ "$output" = 1 ]
}

@test "tiny success interval fetches and emits updated weather end to end" {
  export ISLAND_WEATHER_INTERVAL=1
  start_weather
  assert_weather '29°' 'Cerah' '󰖙'
  printf '{"current_condition":[{"temp_C":"30","weatherCode":"302"}]}\n' > "$WEATHER_FIXTURE/response"
  weather_tick 100001
  next_weather
  assert_weather '30°' 'Hujan lebat' '󰖖'
}

@test "tiny retry interval recovers after failed fetch" {
  export ISLAND_WEATHER_RETRY=1
  printf '22\n' > "$WEATHER_FIXTURE/curl-status"
  start_weather
  [ "$event" = "$EMPTY" ]
  printf '0\n' > "$WEATHER_FIXTURE/curl-status"
  weather_tick 100001
  next_weather
  assert_weather '29°' 'Cerah' '󰖙'
}

@test "valid weather JSON followed by malformed content is unavailable and not cached" {
  printf '{"current_condition":[{"temp_C":"29","weatherCode":"113"}]}garbage\n' \
    > "$WEATHER_FIXTURE/response"
  start_weather
  [ "$event" = "$EMPTY" ]
  [ ! -e "$XDG_CACHE_HOME/eww-island/weather.json" ]
}

@test "location encodes reserved characters and UTF-8 without changing ordinary names" {
  source "$CFG/scripts/weather"
  local location encoded
  while IFS='|' read -r location encoded; do
    printf ' \t%s \n' "$location" > "$CFG/weather-location"
    run weather_location
    [ "$status" -eq 0 ]
    [ "$output" = "$encoded" ]
  done <<'EOF'
Bandung #1?|Bandung%20%231%3F
Yogyakarta|Yogyakarta
São Paulo|S%C3%A3o%20Paulo
EOF
}

@test "backward clock steps keep weather available and rebase the fetch deadline" {
  export ISLAND_WEATHER_INTERVAL=120
  start_weather
  assert_weather '29°' 'Cerah' '󰖙'
  weather_tick 99900
  ! IFS= read -r -t 0.1 -u "$output_fd" event
  printf '{"current_condition":[{"temp_C":"30","weatherCode":"302"}]}\n' \
    > "$WEATHER_FIXTURE/response"
  weather_tick 100060
  next_weather
  assert_weather '30°' 'Hujan lebat' '󰖖'
}
