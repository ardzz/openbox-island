# tests/weather/schedule.bats: weather cache, fetch intervals, retries and clock changes
load common

@test "missing location uses wttr IP geolocation and caches the fetch timestamp" {
  start_weather
  assert_weather '29°' 'Cerah' '󰖙'
  run cat "$WEATHER_FIXTURE/urls"
  [ "$output" = 'https://wttr.in/?format=j1' ]
  run jq -ce '{fetched}' "$XDG_CACHE_HOME/eww-island/weather.json"
  [ "$status" -eq 0 ]
  [ "$output" = '{"fetched":100000}' ]
}

@test "cache older than the interval emits before blocked fetch and recomputes current night glyph" {
  seed_weather_cache 98000
  printf '23\n' > "$WEATHER_FIXTURE/hour"
  printf '' > "$WEATHER_FIXTURE/block-fetch"
  start_weather
  assert_weather '21°' 'Cerah' '󰖔'
  printf 'continue\n' >&"$gate_fd"
  next_weather
  assert_weather '29°' 'Cerah' '󰖔'
}

@test "a restart within the fetch interval reuses the cache without fetching until it is due" {
  seed_weather_cache 99900
  start_weather
  assert_weather '21°' 'Cerah' '󰖙'
  weather_tick 100060
  ! IFS= read -r -t 0.1 -u "$output_fd" event
  [ "$(cat "$WEATHER_FIXTURE/calls")" = 0 ]
  weather_tick 101700
  next_weather
  assert_weather '29°' 'Cerah' '󰖙'
  [ "$(cat "$WEATHER_FIXTURE/calls")" = 1 ]
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
