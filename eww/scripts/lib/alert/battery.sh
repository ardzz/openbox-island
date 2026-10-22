#!/usr/bin/env bash
# Alert source: battery charge state and low levels (upower). Source it; do not execute.

ICON_BAT_LOW=$'\U000F12A1'
ICON_BAT_CHARGING=$'\U000F0084'

# battery_init: the first UPower battery; a machine without one skips silently.
battery_init() {
  local paths
  alert_need upower || return
  # The charging alert notes the conservation limit.
  conservation_find || :
  paths=$(upower -e)
  while IFS= read -r battery_path; do [[ $battery_path == *battery_* ]] && break; done <<< "$paths"
  [[ $battery_path == *battery_* ]]
}

battery_monitor() { printf '%s\0' upower --monitor; }

battery_update() {
  local state=$1 value=$2 text='' icon=$ICON_BAT_FULL kind=battery suffix=''
  if [[ -n ${battery_seen:-} ]]; then
    if [[ $state != "$battery_state" ]]; then
      case $state in
        charging)
          text='Mengisi daya'; icon=$ICON_BAT_CHARGING; kind=charging
          # shellcheck disable=SC2154 # conservation_read sets conservation_value
          if [[ -n ${conservation_file:-} ]] && conservation_read && [[ $conservation_value == 1 ]]; then
            suffix=' · batas 80%'
          fi ;;
        fully-charged) text='Baterai penuh' ;;
        discharging)
          case $battery_state in
            charging|pending-charge|fully-charged) text='Charger dicabut' ;;
          esac ;;
      esac
    fi
    if [[ -n $text ]]; then alert_json "$kind" "$icon" "$text" "$value%$suffix" "$value"; fi
    if [[ $state == discharging ]]; then
      text='' kind=battery-low icon=$ICON_BAT_LOW
      if (( battery_value > 10 && value <= 10 )); then text='Baterai kritis'
      elif (( battery_value > 20 && value <= 20 )); then text='Baterai lemah'; fi
      if [[ -n $text ]]; then alert_json "$kind" "$icon" "$text" "$value%" "$value"; fi
    fi
  fi
  battery_seen=1 battery_state=$state battery_value=$value
}

battery_snapshot() {
  local raw line state='' value=''
  raw=$(upower -i "$battery_path") || return
  while IFS= read -r line; do
    if [[ $line =~ state:[[:space:]]+([^[:space:]]+) ]]; then state=${BASH_REMATCH[1]}; fi
    if [[ $line =~ percentage:[[:space:]]+([0-9]+([.][0-9]+)?)% ]]; then value=${BASH_REMATCH[1]}; fi
  done <<< "$raw"
  [[ -n $state && -n $value ]] || return 1
  value=${value%%.*}
  battery_update "$state" "$((10#$value))"
}

battery_event() {
  [[ $1 == *'device changed:'* && $1 == *"$battery_path"* ]] || return 0
  battery_snapshot
}
