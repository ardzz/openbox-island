#!/usr/bin/env bash
# Headphone source of scripts/status, fed by pactl and bluez. Source it after core.sh; do not execute.

HEADPHONE_NONE='{"kind":"none","icon":"","name":"","battery":null,"battery_icon":"","low":false,"label":""}'
# Battery glyphs for the Musik tab, emptiest first: md-battery_10, _30, _60 and md-battery (full).
HEADPHONE_BATTERY_ICONS=$'\U000F007A \U000F007C \U000F007F \U000F0079'
BLUEZ_RE="PropertiesChanged \\('org\\.bluez\\.(Battery1', \\{.*'Percentage'|Device1', \\{.*'Connected')"

# headphone_snapshot: the default sink as a bluetooth headset, wired headphones or nothing.
headphone_snapshot() {
  local sink json line='' kind=none name='' mac='' info battery='' icon=''
  if sink=$(pactl get-default-sink 2>/dev/null) && json=$(pactl -f json list sinks 2>/dev/null); then
    line=$(jq -r --arg sink "$sink" 'first(.[] | select(.name == $sink)) | . as $s
      | (first(($s.ports // [])[] | select(.name == $s.active_port)) // {}) as $p
      | if ($sink | startswith("bluez_")) then
          ["bt", $s.description // "", $s.properties["api.bluez5.address"]
            // (try ($sink | capture("(?<m>[0-9A-Fa-f]{2}(_[0-9A-Fa-f]{2}){5})").m | gsub("_"; ":")) catch "")]
        elif ([$p.name, $p.description, $p.type, $s.description] | map(. // "") | join(" ")
          | ascii_downcase | test("headphone|headset")) then
          ["wired", $p.description // $s.description // "", ""]
        else ["none", "", ""] end
      | join("\u001f")' <<< "$json" 2>/dev/null) || line=''
  fi
  [[ -n $line ]] && IFS=$'\x1f' read -r kind name mac <<< "$line"
  case $kind in
    bt)
      icon=$ICON_HEADPHONES_BT
      # bluetoothctl waits forever for bluetoothd when the daemon is down.
      if [[ -n $mac ]] && info=$(timeout 3 bluetoothctl info "$mac" 2>/dev/null); then
        while read -r line; do
          case $line in
            'Alias: '?*) name=${line#Alias: } ;;
            'Battery Percentage: '*) if [[ $line =~ \(([0-9]+)\) ]]; then battery=${BASH_REMATCH[1]}; fi ;;
          esac
        done <<< "$info"
      fi ;;
    wired) icon=$ICON_HEADPHONES ;;
    *) headphone_idle; return ;;
  esac
  jq -cn --arg kind "$kind" --arg icon "$icon" --arg name "$name" --arg battery "$battery" \
    --arg icons "$HEADPHONE_BATTERY_ICONS" '
    ($battery | if . == "" then null else tonumber end) as $b | ($icons | split(" ")) as $i |
    {source:"headphone",headphone:{kind:$kind,icon:$icon,name:$name,battery:$b,
      battery_icon:(if $b == null then "" elif $b >= 75 then $i[3] elif $b >= 50 then $i[2]
        elif $b >= 25 then $i[1] else $i[0] end),
      low:($b != null and $b <= 20),label:($name + (if $b == null then "" else " · \($b)%" end))}}'
}

# headphone_sink_event LINE: a pactl subscribe line; server and sink events refresh.
headphone_sink_event() {
  case $1 in
    *' on server'*|*' on sink #'*) headphone_snapshot ;;
  esac
}

# headphone_bluez_event LINE: a gdbus monitor line; battery and connection changes refresh.
headphone_bluez_event() { if [[ $1 =~ $BLUEZ_RE ]]; then headphone_snapshot; fi; }

headphone_idle() { printf '{"source":"headphone","headphone":%s}\n' "$HEADPHONE_NONE"; }
