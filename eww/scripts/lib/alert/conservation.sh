#!/usr/bin/env bash
# Alert source: Lenovo battery conservation mode (charge limit). Source it; do not execute.

ICON_BAT_LIMIT=$'\U000F0081'

conservation_init() { conservation_find || alert_skip 'conservation_mode tidak ditemukan'; }
conservation_interval() { printf '%s' "${ISLAND_CONSERVATION_INTERVAL:-5}"; }

# conservation_find: Lenovo conservation_mode file, ISLAND_CONSERVATION overriding sysfs. Fails when absent.
conservation_find() {
  local file
  conservation_file=''
  if [[ -n ${ISLAND_CONSERVATION:-} ]]; then
    [[ -e $ISLAND_CONSERVATION ]] && conservation_file=$ISLAND_CONSERVATION
  else
    for file in /sys/bus/platform/devices/VPC2004:*/conservation_mode; do
      if [[ -e $file ]]; then conservation_file=$file; break; fi
    done
  fi
  [[ -n $conservation_file ]]
}

conservation_read() {
  local value=''
  IFS= read -r value 2>/dev/null < "$conservation_file" || :
  [[ $value == [01] ]] || return 1
  conservation_value=$value
}

conservation_snapshot() {
  conservation_read || return 0
  if [[ -n ${conservation_state:-} && $conservation_value != "$conservation_state" ]]; then
    if [[ $conservation_value == 1 ]]; then
      alert_json battery "$ICON_BAT_LIMIT" 'Batas pengisian aktif' 80% -1
    else
      alert_json battery "$ICON_BAT_FULL" 'Pengisian penuh' 100% -1
    fi
  fi
  conservation_state=$conservation_value
}
