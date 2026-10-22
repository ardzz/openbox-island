# tests/weather/fetch.bats: wttr.in responses becoming weather events
load common

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

@test "valid weather JSON followed by malformed content is unavailable and not cached" {
  printf '{"current_condition":[{"temp_C":"29","weatherCode":"113"}]}garbage\n' \
    > "$WEATHER_FIXTURE/response"
  start_weather
  [ "$event" = "$EMPTY" ]
  [ ! -e "$XDG_CACHE_HOME/eww-island/weather.json" ]
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
