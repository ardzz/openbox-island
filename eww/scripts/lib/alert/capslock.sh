#!/usr/bin/env bash
# Alert source: Caps Lock HUD (keyboard LEDs). Source it; do not execute.

ICON_CAPS=$'\U000F0632'

capslock_init() { capslock_snapshot > /dev/null || alert_skip 'LED Caps Lock tidak ditemukan'; }
capslock_interval() { printf '%s' "${ISLAND_CAPS_INTERVAL:-0.25}"; }

# capslock_snapshot: Caps Lock is on if any keyboard LED is lit. Fails when no LED exists.
capslock_snapshot() {
  local file value state=off found=0 text='Caps Lock mati'
  for file in "${ISLAND_LEDS:-/sys/class/leds}"/*::capslock/brightness; do
    [[ -e $file ]] || continue
    found=1 value=''
    IFS= read -r value 2>/dev/null < "$file" || :
    if [[ $value =~ ^[0-9]+$ ]] && (( 10#$value )); then state=on; break; fi
  done
  (( found )) || return 1
  if [[ -n ${caps_state:-} && $state != "$caps_state" ]]; then
    if [[ $state == on ]]; then text='Caps Lock nyala'; fi
    alert_json capslock "$ICON_CAPS" "$text" '' -1
  fi
  caps_state=$state
}
