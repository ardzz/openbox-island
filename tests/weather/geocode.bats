# tests/weather/geocode.bats: reverse geocoding of the city and its cache
load common

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
