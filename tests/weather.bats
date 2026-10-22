load helpers

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
  cp "$SCRIPTS/lib.sh" "$CFG/scripts/lib.sh"
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
149|Berkabut|󰖑
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

@test "weather tone follows precipitation first, then heat, then sky and time of day" {
  source "$SCRIPTS/weather"
  local temp code hour tone
  while IFS='|' read -r temp code hour tone; do
    run weather_json "$temp" "$code" "$hour"
    [ "$status" -eq 0 ]
    [ "$(jq -r .tone <<< "$output")" = "$tone" ] || { echo "$temp $code $hour: $output"; false; }
  done <<'EOF'
36|176|12|rain
30|299|12|rain
33|200|12|storm
-2|179|08|snow
34|143|12|fog
33|113|12|hot
33|119|12|hot
33|113|22|hot
28|116|12|warm
32|119|12|warm
27|113|12|sunny
16|116|12|sunny
29|113|22|night
15|113|12|cold
10|119|12|cold
15|113|22|cold
24|119|12|cloud
EOF
}

@test "forecast days carry a daytime tone from their maximum temperature" {
  source "$SCRIPTS/weather"
  run weather_json 25 119 22 '{"days":[{"day":"Hari ini","weatherCode":"113","max":"34","min":"25","rain":"0%"},{"day":"Besok","weatherCode":"113","max":"27","min":"20","rain":"0%"},{"day":"Lusa","weatherCode":"302","max":"35","min":"24","rain":"90%"},{"day":"X","weatherCode":"","max":"","min":"","rain":""}]}'
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.days[].tone]' <<< "$output")" = '["hot","sunny","rain",""]' ]
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

@test "missing location uses wttr IP geolocation and caches the fetch timestamp" {
  start_weather
  assert_weather '29°' 'Cerah' '󰖙'
  run cat "$WEATHER_FIXTURE/urls"
  [ "$output" = 'https://wttr.in/?format=j1' ]
  run jq -ce '{fetched}' "$XDG_CACHE_HOME/eww-island/weather.json"
  [ "$status" -eq 0 ]
  [ "$output" = '{"fetched":100000}' ]
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

@test "realistic weather emits all detail fields and three forecast days in order" {
  realistic_weather
  enable_geocode
  start_weather
  [ "$event" = '{"ok":true,"icon":"󰖑","tone":"fog","temp":"28°","desc":"Berkabut","city":"Surabaya","region":"Jawa Timur","feels":"30°","humidity":"68%","wind":"4 km/j","uv":"0","sunrise":"05:05","sunset":"17:23","days":[{"day":"Hari ini","icon":"󰖑","tone":"fog","max":"35°","min":"26°","rain":"7%"},{"day":"Besok","icon":"󰖖","tone":"rain","max":"34°","min":"25°","rain":"80%"},{"day":"Sab","icon":"󰖕","tone":"hot","max":"33°","min":"24°","rain":"10%"}]}' ]
}

@test "astronomy converts midnight and noon without changing their minutes" {
  realistic_weather
  change_response '.weather[0].astronomy=[{"sunrise":"12:07 AM","sunset":"12:23 PM"}]'
  start_weather
  assert_fields '.sunrise == "00:07" and .sunset == "12:23"'
}

@test "invalid optional fields are empty and invalid forecast temperatures drop only those days" {
  realistic_weather
  change_response '.current_condition[0] += {"FeelsLikeC":"warm","humidity":null,"uvIndex":[],"windspeedKmph":"fast"} | .weather[0].astronomy=[{"sunrise":"bad","sunset":null}] | .weather[0].hourly |= map(.chanceofrain="bad") | .weather[1].maxtempC="hot" | .weather[2].mintempC=null'
  start_weather
  assert_fields '.ok and .temp == "28°" and .feels == "" and .humidity == "" and .wind == "" and .uv == "" and .sunrise == "" and .sunset == "" and (.days|length) == 1 and .days[0].rain == ""'
}

@test "forecast icons remain daytime clear while current clear weather is night" {
  realistic_weather
  change_response '.current_condition[0].weatherCode="113" | .weather[0].hourly[1].weatherCode="113"'
  printf '23\n' > "$WEATHER_FIXTURE/hour"
  start_weather
  assert_fields '.icon == "󰖔" and .days[0].icon == "󰖙"'
}

@test "forecast is limited to three entries" {
  realistic_weather
  change_response '.weather += [.weather[2] | .date="2026-10-25"]'
  start_weather
  assert_fields '(.days|length) == 3'
}

@test "explicit location takes priority over available GeoClue coordinates" {
  enable_geoclue
  printf ' Bandung #1? \n' > "$CFG/weather-location"
  start_weather
  assert_weather '29°' 'Cerah' '󰖙'
  [ ! -e "$WEATHER_FIXTURE/geoclue-calls" ]
  [ "$(cat "$WEATHER_FIXTURE/urls")" = 'https://wttr.in/Bandung%20%231%3F?format=j1' ]
}

@test "GeoClue uses last signed decimal coordinates and overrides wttr coordinates for geocoding" {
  realistic_weather
  enable_geoclue
  enable_geocode
  printf ' \t\n' > "$CFG/weather-location"
  start_weather
  assert_fields '.city == "Surabaya" and .region == "Jawa Timur"'
  [ "$(cat "$WEATHER_FIXTURE/urls")" = 'https://wttr.in/-7.257472%2C112.752090?format=j1' ]
  [ "$(cat "$WEATHER_FIXTURE/geocode-urls")" = 'https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=10&accept-language=id&lat=-7.257472&lon=112.752090' ]
}

@test "failed GeoClue discards otherwise valid coordinates and falls back to IP" {
  enable_geoclue
  printf '1\n' > "$WEATHER_FIXTURE/geoclue-status"
  start_weather
  assert_weather '29°' 'Cerah' '󰖙'
  [ "$(cat "$WEATHER_FIXTURE/urls")" = 'https://wttr.in/?format=j1' ]
}

@test "successful but unparsable GeoClue falls back to IP" {
  printf '0\n' > "$WEATHER_FIXTURE/geoclue-status"
  printf 'Latitude: garbage°\nLongitude: 112.75°\n' > "$WEATHER_FIXTURE/geoclue-response"
  start_weather
  assert_weather '29°' 'Cerah' '󰖙'
  [ "$(cat "$WEATHER_FIXTURE/urls")" = 'https://wttr.in/?format=j1' ]
}

@test "non executable GeoClue falls back to IP" {
  chmod -x "$BIN/where-am-i"
  start_weather
  assert_weather '29°' 'Cerah' '󰖙'
  [ "$(cat "$WEATHER_FIXTURE/urls")" = 'https://wttr.in/?format=j1' ]
}

@test "Nominatim selects the first nonempty city town municipality county or village" {
  realistic_weather
  enable_geocode
  local address expected
  while IFS='|' read -r address expected; do
    printf '{"address":%s}\n' "$address" > "$WEATHER_FIXTURE/geocode-response"
    start_weather
    assert_fields ".city == \"$expected\" and .region == \"Jawa Timur\""
    stop_weather
    rm -f "$XDG_CACHE_HOME/eww-island/weather.json"
    rm -rf "$XDG_CACHE_HOME/eww-island/geocode"
  done <<'EOF'
{"city":"Surabaya","town":"Town","municipality":"Municipality","county":"County","village":"Village","state":"Jawa Timur"}|Surabaya
{"city":"","town":"Town","municipality":"Municipality","county":"County","village":"Village","state":"Jawa Timur"}|Town
{"town":"","municipality":"Municipality","county":"County","village":"Village","state":"Jawa Timur"}|Municipality
{"municipality":"","county":"County","village":"Village","state":"Jawa Timur"}|County
{"county":"","village":"Village","state":"Jawa Timur"}|Village
EOF
}

@test "geocode cache uses rounded coordinates and avoids another request on subsequent fetch" {
  realistic_weather
  enable_geocode
  export ISLAND_WEATHER_INTERVAL=1
  start_weather
  assert_fields '.city == "Surabaya" and .region == "Jawa Timur"'
  run jq -ce '.' "$XDG_CACHE_HOME/eww-island/geocode/-7.25_112.75.json"
  [ "$status" -eq 0 ]
  [ "$output" = '{"city":"Surabaya","region":"Jawa Timur"}' ]
  change_response '.current_condition[0].temp_C="31"'
  printf '22\n' > "$WEATHER_FIXTURE/geocode-status"
  weather_tick 100001
  next_weather
  assert_fields '.temp == "31°" and .city == "Surabaya"'
  run cat "$WEATHER_FIXTURE/geocode-urls"
  [ "${#lines[@]}" -eq 1 ]
}

@test "expired geocode cache is refreshed after thirty days" {
  realistic_weather
  enable_geocode
  export ISLAND_WEATHER_INTERVAL=2592000
  start_weather
  assert_fields '.city == "Surabaya"'
  printf '{"address":{"city":"Kota Baru","state":"Wilayah Baru"}}\n' > "$WEATHER_FIXTURE/geocode-response"
  weather_tick 2692000
  next_weather
  assert_fields '.city == "Kota Baru" and .region == "Wilayah Baru"'
  run cat "$WEATHER_FIXTURE/geocode-urls"
  [ "${#lines[@]}" -eq 2 ]
}

@test "geocode failure malformed JSON or missing city preserves wttr area and region without caching" {
  realistic_weather
  local response
  for response in '{}' 'not json' '{"address":{"state":"Jawa Timur","city":""}}'; do
    printf '%s\n' "$response" > "$WEATHER_FIXTURE/geocode-response"
    printf '0\n' > "$WEATHER_FIXTURE/geocode-status"
    start_weather
    assert_fields '.ok and .city == "Alun-Aluncontong" and .region == "East Java"'
    [ ! -e "$XDG_CACHE_HOME/eww-island/geocode/-7.25_112.75.json" ]
    stop_weather
    rm -f "$XDG_CACHE_HOME/eww-island/weather.json"
  done
  printf '22\n' > "$WEATHER_FIXTURE/geocode-status"
  start_weather
  assert_fields '.ok and .city == "Alun-Aluncontong" and .region == "East Java"'
}

@test "area names survive absent coordinates without a reverse request" {
  realistic_weather
  change_response 'del(.nearest_area[0].latitude,.nearest_area[0].longitude)'
  start_weather
  assert_fields '.city == "Alun-Aluncontong" and .region == "East Java"'
  [ ! -e "$WEATHER_FIXTURE/geocode-urls" ]
}

@test "fresh old format weather cache is ignored" {
  printf '{"temp_C":"21","weatherCode":"113","fetched":99900}\n' \
    > "$XDG_CACHE_HOME/eww-island/weather.json"
  printf '22\n' > "$WEATHER_FIXTURE/curl-status"
  start_weather
  [ "$event" = "$EMPTY" ]
}

@test "fresh detailed cache retains all details and recomputes the current hour icon" {
  realistic_weather
  enable_geocode
  change_response '.current_condition[0].weatherCode="113"'
  start_weather
  assert_fields '.city == "Surabaya" and (.days|length) == 3'
  local previous=$event
  stop_weather
  printf '23\n' > "$WEATHER_FIXTURE/hour"
  printf '' > "$WEATHER_FIXTURE/block-fetch"
  start_weather
  [ "$(jq -r .tone <<< "$previous")" = warm ]
  [ "$event" = "$(jq -c '.icon="󰖔" | .tone="night"' <<< "$previous")" ]
}
