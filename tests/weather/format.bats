# tests/weather/format.bats: weather glyphs, descriptions and tones
load common

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
