#!/usr/bin/env bash
# Alert source: Wi-Fi connect and disconnect (nmcli). Source it; do not execute.

ICON_WIFI_4=$'\U000F0928'
ICON_WIFI_OFF=$'\U000F092D'
declare -gA wifi_states=()

wifi_init() { alert_need nmcli; }
wifi_monitor() { printf '%s\0' nmcli monitor; }

wifi_snapshot() {
  local devices dev type state
  devices=$(nmcli -t -f DEVICE,TYPE device) || return
  while IFS=: read -r dev type; do
    [[ $type == wifi ]] || continue
    state=$(nmcli -t -g GENERAL.STATE device show "$dev") || continue
    if [[ $state == '100 '* || $state == 100 || $state == connected ]]; then
      wifi_states[$dev]=connected
    else
      wifi_states[$dev]=disconnected
    fi
  done <<< "$devices"
}

wifi_event() {
  local dev=${1%%:*} state=${1#*: } connection='' icon text
  [[ -n ${wifi_states[$dev]+set} ]] || return 0
  case $state in
    connected) icon=$ICON_WIFI_4; text='Wi-Fi tersambung' ;;
    disconnected) icon=$ICON_WIFI_OFF; text='Wi-Fi terputus' ;;
    *) return 0 ;;
  esac
  [[ $state != "${wifi_states[$dev]}" ]] || return 0
  wifi_states[$dev]=$state
  if [[ $state == connected ]]; then
    connection=$(nmcli -t -g GENERAL.CONNECTION device show "$dev") || return
  fi
  alert_json wifi "$icon" "$text" "$connection" -1
}
