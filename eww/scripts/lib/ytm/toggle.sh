#!/usr/bin/env bash
# `ytm toggle-like|toggle-dislike`: change the like status of the shown track. Source it after core.sh.

# toggle_action KIND CURRENT: "<ytm subcommand> <resulting status>".
toggle_action() {
  local kind=$1 current=$2 set=LIKE
  [[ $kind == dislike ]] && set=DISLIKE
  if [[ $current == "$set" ]]; then echo "unlike INDIFFERENT"; else echo "$kind $set"; fi
}

# toggle KIND: run the ytm subcommand and hand the new status to the listener through ytm_set.
toggle() {
  local kind=$1 active vid like cmd new
  command -v "$YTM" >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || return 0
  { IFS= read -r active; IFS= read -r vid; IFS= read -r like; } < <(
    jq -r '.active, .video_id, .like' "$ISLAND_STATE/ytm.json" 2>/dev/null)
  [[ $active == true ]] || return 0
  read -r cmd new < <(toggle_action "$kind" "$like")
  "$YTM" "$cmd" >/dev/null 2>&1 || return 1
  [[ -n $vid ]] || return 0
  printf '%s\t%s\n' "$vid" "$new" > "$ISLAND_STATE/ytm_set.tmp"
  mv "$ISLAND_STATE/ytm_set.tmp" "$ISLAND_STATE/ytm_set"
}
