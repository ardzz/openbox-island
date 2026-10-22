#!/usr/bin/env bash
# wttr.in fetch and the weather cache files. Source it after core.sh and weather/location.sh.
declare -g CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/eww-island/weather.json"

# write_weather_cache PATH JSON: replace PATH atomically.
write_weather_cache() {
  local path=$1 record=$2 file
  mkdir -p "${path%/*}" || return 1
  file=$(mktemp "$path.XXXXXX") || return 1
  if printf '%s\n' "$record" > "$file" && mv "$file" "$path"; then return 0; fi
  rm -f "$file"
  return 1
}

# read_weather_cache: the cached record when CACHE holds a valid one (with .fetched), else nothing.
read_weather_cache() {
  [[ -r $CACHE ]] || return 0
  jq -ce 'select((.fetched|type)=="number" and (.fetched|floor)==.fetched and .fetched>=0) |
    select((.temp_C|type)=="string" and (.temp_C|test("^-?[0-9]+$"))) |
    select((.weatherCode|type)=="string" and (.weatherCode|test("^-?[0-9]+$"))) |
    select([.city,.region,.feels,.humidity,.wind,.uv,.sunrise,.sunset] | all(type=="string")) |
    select((.days|type)=="array")' "$CACHE" 2>/dev/null
}

# fetch_weather: one wttr.in request -> a weather record, its city replaced by the reverse geocode.
fetch_weather() {
  local response record coordinates lat lon city
  weather_location >/dev/null
  response=$(curl -sf --max-time 8 "https://wttr.in/$WEATHER_LOCATION?format=j1") || return 1
  record=$(jq -sce '
    def integer:
      if (type=="string" or type=="number") and (tostring|test("^-?[0-9]+$")) then tostring else "" end;
    def unit($suffix): integer | if .=="" then "" else .+$suffix end;
    def text: if type=="string" then . else "" end;
    def array: if type=="array" then . else [] end;
    def clock:
      if type!="string" then "" else
        (try (capture("^(?<h>0?[1-9]|1[0-2]):(?<m>[0-5][0-9]) (?<p>AM|PM)$") |
          (((.h|tonumber)%12 + (if .p=="PM" then 12 else 0 end)) | tostring) as $h |
          (if ($h|length)==1 then "0"+$h else $h end)+":"+.m) catch "") // ""
      end;
    select(length==1) | .[0] as $root |
    $root.current_condition[0] as $c |
    ($c.temp_C|integer) as $temp | ($c.weatherCode|integer) as $code |
    select($temp!="" and $code!="") |
    {temp_C:$temp,weatherCode:$code,
     city:((try $root.nearest_area[0].areaName[0].value catch null)|text),
     region:((try $root.nearest_area[0].region[0].value catch null)|text),
     feels:($c.FeelsLikeC|unit("°")),humidity:($c.humidity|unit("%")),
     wind:($c.windspeedKmph|unit(" km/j")),uv:($c.uvIndex|integer),
     sunrise:((try $root.weather[0].astronomy[0].sunrise catch null)|clock),
     sunset:((try $root.weather[0].astronomy[0].sunset catch null)|clock),
     days:[($root.weather|array)[:3] | to_entries[] |
       .key as $index | .value | select(type=="object") |
       (.maxtempC|integer) as $max | (.mintempC|integer) as $min |
       select($max!="" and $min!="") |
       (.hourly|array|map(select(type=="object"))) as $hours |
       {day:(if $index==0 then "Hari ini" elif $index==1 then "Besok" else
         (try (.date|strptime("%Y-%m-%d")|mktime|strftime("%w")|tonumber|
          ["Min","Sen","Sel","Rab","Kam","Jum","Sab"][.]) catch "") end),
        weatherCode:((([$hours[] | select(.time=="1200" or .time==1200)][0] // $hours[0]).weatherCode)|integer),
        max:($max+"°"),min:($min+"°"),
        rain:([$hours[] | .chanceofrain|integer|select(.!="")|tonumber] | if length==0 then "" else (max|tostring)+"%" end)}]}
  ' <<< "$response" 2>/dev/null) || return 1
  lat=$WEATHER_LAT lon=$WEATHER_LON
  if [[ -z $lat || -z $lon ]]; then
    coordinates=$(jq -r '[(try .nearest_area[0].latitude catch ""),(try .nearest_area[0].longitude catch "")] | @tsv' <<< "$response" 2>/dev/null)
    IFS=$'\t' read -r lat lon <<< "$coordinates"
  fi
  if city=$(geocode_weather "$lat" "$lon"); then
    record=$(jq -c --argjson city "$city" '. + $city' <<< "$record")
  fi
  printf '%s\n' "$record"
}
