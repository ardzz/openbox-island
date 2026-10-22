#!/usr/bin/env bash
# Camera source of scripts/status. Source it; do not execute.

camera_devices=()

# camera_find: collect the video devices under ISLAND_DEV (/dev); 1 when there is none.
camera_find() {
  local device
  camera_devices=()
  for device in "${ISLAND_DEV:-/dev}"/video*; do
    [[ -e $device ]] && camera_devices+=("$device")
  done
  (( ${#camera_devices[@]} ))
}

# camera_snapshot: the processes (but this one) holding a video device open, by their comm names.
camera_snapshot() {
  local pid name device pattern names=''
  local active=false
  local -a matches=()
  for device in "${camera_devices[@]}"; do
    pattern=${device//\\/\\\\}
    pattern=${pattern//\*/\\*}
    pattern=${pattern//\?/\\?}
    pattern=${pattern//\[/\\[}
    (( ${#matches[@]} )) && matches+=(-o)
    matches+=(-lname "$pattern")
  done
  while IFS= read -r -d '' pid; do
    pid=${pid%/fd}
    [[ ${pid##*/} != "$$" ]] || continue
    active=true
    name=''
    if [[ -r $pid/comm ]]; then IFS= read -r name < "$pid/comm" || :; fi
    names+="$name"$'\n'
  done < <(find "${ISLAND_PROC:-/proc}"/[0-9]*/fd -maxdepth 1 -type l -readable \
    \( "${matches[@]}" \) -printf '%h\0' 2>/dev/null)
  jq -cn --argjson active "$active" --arg names "$names" '
    {source:"camera",active:$active,apps:($names | split("\n") |
      map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0)) | unique | join(", "))}'
}

# camera_event LINE: any inotify open or close rescans.
camera_event() { camera_snapshot; }

camera_idle() { printf '{"source":"camera","active":false,"apps":""}\n'; }
