#!/usr/bin/env bash
# Alert source: Bluetooth device connect and disconnect (gdbus, bluetoothctl). Source it; do not execute.

ICON_BT=$'\U000F00AF'
ICON_GAMEPAD=$'\U000F0297'
ICON_MOUSE=$'\U000F037D'
ICON_KEYBOARD=$'\U000F030C'
ICON_PHONE=$'\U000F011C'
BT_CONNECTED_RE="^/org/bluez/hci[0-9]+/dev_([0-9A-Fa-f_]{17}): org\\.freedesktop\\.DBus\\.Properties\\.PropertiesChanged \\('org\\.bluez\\.Device1', \\{.*'Connected': <(true|false)>"
declare -gA bt_states=()

bluetooth_init() { alert_need gdbus bluetoothctl; }
bluetooth_monitor() { printf '%s\0' gdbus monitor --system --dest org.bluez; }

bluetooth_snapshot() {
  local devices word mac rest
  # bluetoothctl waits forever for bluetoothd when the daemon is down.
  devices=$(timeout 3 bluetoothctl devices Connected) || return
  bt_states=()
  while read -r word mac rest; do
    if [[ $word == Device ]]; then bt_states[$mac]=yes; fi
  done <<< "$devices"
}

bluetooth_event() {
  local mac state info line alias='' device='' battery='' icon text
  [[ $1 =~ $BT_CONNECTED_RE ]] || return 0
  mac=${BASH_REMATCH[1]//_/:} state=no
  if [[ ${BASH_REMATCH[2]} == true ]]; then state=yes; fi
  [[ $state != "${bt_states[$mac]:-no}" ]] || return 0
  bt_states[$mac]=$state
  info=$(timeout 3 bluetoothctl info "$mac") || info=''
  while read -r line; do
    case $line in
      'Alias: '*) alias=${line#Alias: } ;;
      'Icon: '*) device=${line#Icon: } ;;
      'Battery Percentage: '*) if [[ $line =~ \(([0-9]+)\) ]]; then battery=${BASH_REMATCH[1]}; fi ;;
    esac
  done <<< "$info"
  alias=${alias:-$mac}
  case $device in
    audio-*|*headset*) icon=$ICON_HEADPHONES ;;
    input-gaming) icon=$ICON_GAMEPAD ;;
    input-mouse) icon=$ICON_MOUSE ;;
    input-keyboard) icon=$ICON_KEYBOARD ;;
    phone) icon=$ICON_PHONE ;;
    *) icon=$ICON_BT ;;
  esac
  text='Bluetooth terputus'
  if [[ $state == yes ]]; then
    text='Bluetooth tersambung'
    if [[ -n $battery ]]; then alias+=" · $battery%"; fi
  fi
  alert_json bluetooth "$icon" "$text" "$alias" -1
}
