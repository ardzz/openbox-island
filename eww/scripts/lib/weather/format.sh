#!/usr/bin/env bash
# Weather JSON for the island: WWO code glyphs, Indonesian descriptions and icon tones.
# Source it after core.sh.
# shellcheck disable=SC2034 # read by scripts/weather
declare -g NONE_JSON='{"ok":false,"icon":"","tone":"","temp":"","desc":"","city":"","region":"","feels":"","humidity":"","wind":"","uv":"","sunrise":"","sunset":"","days":[]}'

# weather_json TEMP CODE HOUR [RECORD]: the island event for a fetched or cached RECORD.
weather_json() {
  local temp=$1 code=$2 hour=$3 record=${4:-}
  [[ -n $record ]] || record='{}'
  jq -nc --arg temp "$temp" --arg code "$code" --arg hour "$hour" --argjson record "$record" '
    def traits:
      tostring as $c |
      if $c == "113" then ["󰖙","Cerah","clear"]
      elif $c == "116" then ["󰖕","Cerah berawan","clear"]
      elif ["143","149","248","260"] | index($c) then ["󰖑","Berkabut","fog"]
      elif ["176","185","263","266","281","284","293","296","311","314","353"] | index($c) then ["󰖗","Hujan ringan","rain"]
      elif ["299","302","305","308","356","359"] | index($c) then ["󰖖","Hujan lebat","rain"]
      elif ["200","386","389","392","395"] | index($c) then ["󰖓","Badai petir","storm"]
      elif ["179","182","227","230","317","320","323","326","329","332","335","338","350","362","365","368","371","374","377"] | index($c) then ["󰖘","Salju","snow"]
      else ["󰖐","Berawan","cloud"] end;
    # Icon colour class: precipitation and fog win, then heat, then sky and time of day.
    def tone($temp; $night):
      (traits[2]) as $sky | ($temp | tostring | sub("[^-0-9]"; ""; "g") | tonumber) as $t |
      if ["rain","storm","snow","fog"] | index($sky) then $sky
      elif $t >= 33 then "hot"
      elif $t <= 15 then "cold"
      elif $sky == "clear" and $night and . == "113" then "night"
      elif $t >= 28 then "warm"
      elif $sky == "clear" then "sunny"
      else "cloud" end;
    (($hour|tonumber) < 6 or ($hour|tonumber) >= 18) as $night |
    ($code | traits) as $current |
    {ok:true,
     icon:(if $code == "113" and $night then "󰖔" else $current[0] end),
     tone:($code | tone($temp; $night)),
     temp:($temp + "°"),desc:$current[1],
     city:($record.city // ""),region:($record.region // ""),
     feels:($record.feels // ""),humidity:($record.humidity // ""),wind:($record.wind // ""),
     uv:($record.uv // ""),sunrise:($record.sunrise // ""),sunset:($record.sunset // ""),
     days:[$record.days[]? | {day,
       icon:(if .weatherCode == "" then "" else (.weatherCode|traits)[0] end),
       tone:(if .weatherCode == "" or .max == "" then "" else (.max as $max | .weatherCode | tostring | tone($max; false)) end),
       max,min,rain}]}
  '
}
