# tests/weather/location.bats: weather location: config file, GeoClue and URL encoding
load common

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
