#!/usr/bin/env bash
# Alert source: ACPI platform profile changes, Fn+Q. Source it; do not execute.

ICON_POWER_SAVER=$'\U000F032A'
ICON_POWER_BALANCED=$'\U000F05D1'
ICON_POWER_PERFORMANCE=$'\U000F04C5'
ICON_POWER_MAX=$'\U000F0463'
ICON_POWER_CUSTOM=$'\U000F062E'

power_init() { power_snapshot > /dev/null || alert_skip 'platform_profile tidak ditemukan'; }
power_interval() { printf '%s' "${ISLAND_POWER_INTERVAL:-2}"; }

# power_snapshot: alert on platform profile changes. Fails when the file is unreadable.
power_snapshot() {
  local profile='' icon=$ICON_POWER_CUSTOM value
  IFS= read -r profile 2>/dev/null < "${ISLAND_PLATFORM_PROFILE:-/sys/firmware/acpi/platform_profile}" || [[ -n $profile ]] || return 1
  if [[ -n ${power_profile:-} && $profile != "$power_profile" ]]; then
    value=$profile
    case $profile in
      low-power) icon=$ICON_POWER_SAVER value='Hemat daya' ;;
      balanced) icon=$ICON_POWER_BALANCED value=Seimbang ;;
      performance) icon=$ICON_POWER_PERFORMANCE value=Performa ;;
      max-power) icon=$ICON_POWER_MAX value='Daya maksimum' ;;
      custom) value=Kustom ;;
    esac
    alert_json power "$icon" 'Mode daya' "$value" -1
  fi
  power_profile=$profile
}
