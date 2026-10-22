#!/usr/bin/env bash
# Alert JSON and icons shared by the alert sources. Source it; do not execute.

# shellcheck disable=SC2034 # read by the battery and conservation sources
ICON_BAT_FULL=$'\U000F0079'

# level_icon LEVEL LOW MID HIGH: the icon for a 0-100 level.
level_icon() {
  if (( $1 < 34 )); then printf '%s' "$2"
  elif (( $1 < 67 )); then printf '%s' "$3"
  else printf '%s' "$4"; fi
}

# alert_json KIND ICON TEXT VALUE LEVEL [IMAGE_PATH]: the image becomes a percent-encoded file URI for CSS url().
alert_json() {
  jq -cn --arg kind "$1" --arg icon "$2" --arg text "$3" \
    --arg value "$4" --argjson level "$5" --arg image "${6:-}" \
    '{kind:$kind,icon:$icon,text:$text,value:$value,level:$level,
      image:(if $image == "" then "" else "file://" + ($image | split("/") | map(@uri) | join("/")) end)}'
}
