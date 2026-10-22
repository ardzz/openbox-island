#!/usr/bin/env bash
# Alert source: CPU and GPU overheating (hwmon). Source it; do not execute.

ICON_THERMOMETER=$'\U000F050F'
declare -gA temp_inputs=() temp_states=()

temperature_init() { temperature_find || alert_skip 'sensor suhu tidak ditemukan'; }
temperature_interval() { printf '%s' "${ISLAND_TEMP_INTERVAL:-5}"; }

# temperature_find: pick the CPU and GPU hwmon inputs by label. Fails when neither exists.
temperature_find() {
  local file label
  local -A inputs=()
  temp_inputs=() temp_states=()
  for file in "${ISLAND_HWMON:-/sys/class/hwmon}"/hwmon*/temp*_label; do
    label=''
    IFS= read -r label 2>/dev/null < "$file" || :
    [[ -n $label && -z ${inputs[$label]:-} ]] || continue
    inputs[$label]=${file%_label}_input
  done
  for label in 'CPU Temperature' 'Package id 0' Tctl; do
    if [[ -n ${inputs[$label]:-} ]]; then temp_inputs[cpu]=${inputs[$label]}; break; fi
  done
  if [[ -n ${inputs['GPU Temperature']:-} ]]; then temp_inputs[gpu]=${inputs['GPU Temperature']}; fi
  (( ${#temp_inputs[@]} ))
}

# temperature_update SENSOR MILLIDEGREES: warn on reaching the threshold, re-arm 5 °C below it.
temperature_update() {
  local sensor=$1 celsius threshold=${ISLAND_TEMP_GPU:-87} text='GPU panas'
  [[ $2 =~ ^[0-9]+$ ]] || return 0
  celsius=$((10#$2 / 1000))
  if [[ $sensor == cpu ]]; then threshold=${ISLAND_TEMP_CPU:-95} text='CPU panas'; fi
  case ${temp_states[$sensor]:-} in
    armed)
      if (( celsius >= threshold )); then
        temp_states[$sensor]=hot
        alert_json temperature "$ICON_THERMOMETER" "$text" "${celsius}°C" -1
      fi ;;
    hot) if (( celsius < threshold - 5 )); then temp_states[$sensor]=armed; fi ;;
    *) temp_states[$sensor]=armed; if (( celsius >= threshold )); then temp_states[$sensor]=hot; fi ;;
  esac
}

temperature_snapshot() {
  local sensor value
  for sensor in cpu gpu; do
    [[ -n ${temp_inputs[$sensor]:-} ]] || continue
    value=''
    IFS= read -r value 2>/dev/null < "${temp_inputs[$sensor]}" || :
    temperature_update "$sensor" "$value"
  done
}
