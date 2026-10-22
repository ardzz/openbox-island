#!/usr/bin/env bash
# playerctl metadata records and the island JSON they become. Source it after core.sh and media/art.sh.

SEP=$'\x1f'
REC=$'\x1e'
# shellcheck disable=SC2034 # read by scripts/media
FORMAT="{{status}}$SEP{{playerInstance}}$SEP{{title}}$SEP{{artist}}$SEP{{mpris:artUrl}}$SEP{{mpris:length}}$REC"
NONE_JSON='{"state":"none","player":"","title":"","artist":"","art":"","length":0,"length_text":"0:00"}'

# media_json RECORD: one playerctl --format "$FORMAT" record -> island JSON. Empty record = no player.
media_json() {
  local status player title artist art_url length state
  IFS=$SEP read -r -d '' status player title artist art_url length < <(printf '%s' "$1")
  case $status in
    Playing) state=playing ;;
    Paused) state=paused ;;
    *) printf '%s\n' "$NONE_JSON"; return 0 ;;
  esac
  [[ $length =~ ^[0-9]+$ ]] || length=0
  length=$(( 10#$length / 1000000 ))
  jq -nc --arg state "$state" --arg player "$player" --arg title "$title" --arg artist "$artist" \
     --arg art "$(resolve_art "$art_url")" --argjson length "$length" \
     --arg length_text "$(fmt_time "$length")" \
     '{state: $state, player: $player, title: $title, artist: $artist, art: $art, length: $length, length_text: $length_text}'
}

# track_key RECORD: identity of the shown track; "" when nothing is playing or paused.
track_key() {
  local status player title artist
  IFS=$SEP read -r -d '' status player title artist _ < <(printf '%s' "$1")
  case $status in
    Playing|Paused) printf '%s\n' "$player$SEP$title$SEP$artist" ;;
    *) printf '\n' ;;
  esac
}

# has_track RECORD: the record names a playing or paused track; mid-change players drop the title.
has_track() {
  local status title
  IFS=$SEP read -r -d '' status _ title _ < <(printf '%s' "$1")
  [[ $status == Playing || $status == Paused ]] && [[ -n $title ]]
}
