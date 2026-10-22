#!/usr/bin/env bash
# Where the weather is for: eww/weather-location, else GeoClue, plus a cached reverse geocode.
# Source it after core.sh and weather/fetch.sh.
declare -g GEOCODE_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/eww-island/geocode"
declare -g WEATHER_LOCATION='' WEATHER_LAT='' WEATHER_LON=''

# weather_location: set and print WEATHER_LOCATION (URI-encoded, "" = wttr IP geolocation);
# WEATHER_LAT and WEATHER_LON hold GeoClue's coordinates when they decided it.
weather_location() {
  local location='' helper=${ISLAND_GEOCLUE_WHEREAMI:-/usr/lib/geoclue-2.0/demos/where-am-i} response line
  WEATHER_LAT='' WEATHER_LON=''
  if [[ -r $ISLAND_CFG/weather-location ]]; then
    location=$(< "$ISLAND_CFG/weather-location")
    location="${location#"${location%%[![:space:]]*}"}"
    location="${location%"${location##*[![:space:]]}"}"
  fi
  if [[ -z $location && -x $helper ]] && response=$(timeout 15 "$helper" -t 10 2>/dev/null); then
    while IFS= read -r line; do
      if [[ $line =~ Latitude:[[:space:]]*(.*) ]]; then WEATHER_LAT=${BASH_REMATCH[1]}; fi
      if [[ $line =~ Longitude:[[:space:]]*(.*) ]]; then WEATHER_LON=${BASH_REMATCH[1]}; fi
    done <<< "$response"
    WEATHER_LAT=${WEATHER_LAT%°} WEATHER_LON=${WEATHER_LON%°}
    if [[ $WEATHER_LAT =~ ^[+-]?[0-9]+([.][0-9]+)?$ && $WEATHER_LON =~ ^[+-]?[0-9]+([.][0-9]+)?$ ]]; then
      location="$WEATHER_LAT,$WEATHER_LON"
    else
      WEATHER_LAT='' WEATHER_LON=''
    fi
  fi
  WEATHER_LOCATION=$(jq -nr --arg location "$location" '$location | @uri')
  printf '%s\n' "$WEATHER_LOCATION"
}

# geocode_weather LAT LON: {city,region} from Nominatim, cached 30 days per 0.01° cell.
geocode_weather() {
  local lat=$1 lon=$2 key path now modified response city
  [[ $lat =~ ^[+-]?[0-9]+([.][0-9]+)?$ && $lon =~ ^[+-]?[0-9]+([.][0-9]+)?$ ]] || return 1
  printf -v key '%.2f_%.2f' "$lat" "$lon"
  path="$GEOCODE_CACHE/$key.json"
  now=$(date +%s)
  if [[ -r $path ]] && modified=$(stat -c %Y "$path" 2>/dev/null) &&
      (( now >= modified && now - modified < 2592000 )); then
    if city=$(jq -ce 'select((.city|type)=="string" and (.city|length)>0 and (.region|type)=="string") | {city,region}' "$path" 2>/dev/null); then
      printf '%s\n' "$city"
      return 0
    fi
  fi
  response=$(curl -sf --max-time 8 -H 'User-Agent: openbox-island/1.0 (+https://github.com/ardzz/openbox-island)' \
    "https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=10&accept-language=id&lat=$lat&lon=$lon") || return 1
  city=$(jq -sce '
    select(length == 1) | .[0].address |
    {city:([.city,.town,.municipality,.county,.village] | map(select(type=="string" and length>0)) | .[0]),
     region:(if (.state|type)=="string" then .state else "" end)} |
    select(.city != null)
  ' <<< "$response" 2>/dev/null) || return 1
  write_weather_cache "$path" "$city" || :
  printf '%s\n' "$city"
}
