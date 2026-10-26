#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=eww/scripts/lib/core.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../core.sh"

mkdir -p "$ISLAND_STATE" || exit 1
input=$(mktemp "$ISLAND_STATE/.ytm-input.XXXXXX") || exit 1
output=$(mktemp "$ISLAND_STATE/.ytm-output.XXXXXX") || { rm -f "$input"; exit 1; }
trap 'rm -f "$input" "$output"' EXIT

while true; do
  read -r -a bytes <<< "$(dd bs=4 count=1 iflag=fullblock status=none | od -An -tu1)"
  (( ${#bytes[@]} == 4 )) || break
  length=$((bytes[0] + (bytes[1] << 8) + (bytes[2] << 16) + (bytes[3] << 24)))
  (( length > 0 )) || continue
  dd bs="$length" count=1 iflag=fullblock status=none > "$input" || break
  [[ $(wc -c < "$input") -eq $length ]] || break
  now=$(date +%s%3N)
  if jq -ces --argjson now "$now" '
    if length == 1 then .[0] else error("satu objek diperlukan") end
    | select(type == "object")
    | select((.title | type) == "string" and (.artist | type) == "string")
    | select((has("ts") | not) or (.ts | type) == "number")
    | .ts = $now' "$input" > "$output" 2>/dev/null; then
    mv -f "$output" "$ISLAND_STATE/ytm-browser.json" || exit 1
  fi
done
