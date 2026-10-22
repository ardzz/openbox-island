#!/usr/bin/env bash
# Default audio output switches, part of the audio source. Source it; do not execute.

ICON_MONITOR=$'\U000F0379'
ICON_SPEAKER=$'\U000F04C3'

# output_snapshot: alert when the default sink or its active port changes.
output_snapshot() {
  local sink json line port value match icon=$ICON_SPEAKER
  sink=$(pactl get-default-sink) || return
  json=$(pactl -f json list sinks) || return
  line=$(jq -r --arg sink "$sink" 'first(.[] | select(.name == $sink)) | . as $s
    | ($s.ports // []) as $ports
    | (first($ports[] | select(.name == $s.active_port)) // {}) as $p
    | [$s.active_port // "",
       (if ($ports | length) > 1 and $p.description then $p.description else $s.description // $sink end),
       ([$p.name, $p.description, $s.description] | map(. // "") | join(" ") | ascii_downcase)]
    | join("\u001f")' <<< "$json") || return
  [[ -n $line ]] || return 1
  IFS=$'\x1f' read -r port value match <<< "$line"
  if [[ -n ${output_key:-} && "$sink/$port" != "$output_key" ]]; then
    if [[ $sink == bluez_* ]]; then icon=$ICON_HEADPHONES_BT
    elif [[ $match == *headphone* || $match == *headset* ]]; then icon=$ICON_HEADPHONES
    elif [[ $match == *hdmi* || $match == *displayport* ]]; then icon=$ICON_MONITOR; fi
    alert_json output "$icon" 'Output audio' "$value" -1
  fi
  output_key=$sink/$port
}
