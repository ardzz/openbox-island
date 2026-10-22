#!/usr/bin/env bash
# Alert source: backlight brightness (light, udevadm). Source it; do not execute.

ICON_BRI_LOW=$'\U000F00DE'
ICON_BRI_MID=$'\U000F00DF'
ICON_BRI_HIGH=$'\U000F00E0'

brightness_init() { alert_need light udevadm; }
brightness_monitor() { printf '%s\0' udevadm monitor --udev --subsystem-match=backlight; }

brightness_update() {
  local value=${1%%.*} icon
  [[ $value =~ ^[0-9]+$ ]] || return 0
  value=$((10#$value))
  if [[ -n ${brightness_seen:-} && $value != "$brightness_value" ]]; then
    icon=$(level_icon "$value" "$ICON_BRI_LOW" "$ICON_BRI_MID" "$ICON_BRI_HIGH")
    alert_json brightness "$icon" Kecerahan "$value%" "$value"
  fi
  brightness_seen=1 brightness_value=$value
}

brightness_snapshot() {
  local value
  value=$(light -G) || return
  brightness_update "$value"
}

brightness_event() {
  [[ $1 == UDEV* ]] || return 0
  brightness_snapshot || return
  if [[ ${worker_mode:-0} == 1 ]]; then printf '@refresh brightness\n'; fi
}
