#!/usr/bin/env bash
# Track transitions: the grace period between tracks, its loading state and the island action.
# Source it after core.sh.

# grace_us: how long (ISLAND_MEDIA_GRACE seconds, default 1.5) a shown track may go missing before
# the music counts as stopped; players report no track for a moment while changing tracks. 0 = never wait.
grace_us() {
  local grace=${ISLAND_MEDIA_GRACE:-1.5}
  [[ $grace =~ ^[0-9]+(\.[0-9]+)?$ ]] || grace=1.5
  seconds_us "$grace"
}

# loading_json PLAYER: the shown player is between tracks; the island draws a skeleton.
loading_json() {
  jq -nc --arg player "$1" \
    '{state: "loading", player: $player, title: "", artist: "", art: "", color: "", length: 0, length_text: "0:00"}'
}

# media_action FIRST PREV_KEY KEY STATUS: auto = a new track started playing (never on the
# first update), close = the shown player went away, none = nothing to do.
media_action() {
  local first=$1 prev=$2 key=$3 status=$4
  if [[ -z $key ]]; then
    if [[ -n $prev ]]; then echo close; else echo none; fi
  elif (( first )); then
    echo none
  elif [[ $key != "$prev" && $status == Playing ]]; then
    echo auto
  else
    echo none
  fi
}
