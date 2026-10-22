#!/usr/bin/env bash
# dunst history as the notification center lists it. Source it after core.sh and notify/clean.sh.
# Every notification skips its popup (dunst-osd.conf), so dunst keeps them all in its history with
# their ids; it outlives island restarts and history-rm/history-clear act on it.

# dunstctl history -> its entries the island shows, newest first. dunst stores a copy per update of the
# same id or app + stack tag (they skip the display queues that replace them); the newest stands for all.
HISTORY_ITEMS_JQ="$CLEAN_JQ"'
  def v($key): .[$key].data // "";
  [(.data[0] // [])[] | objects
   | {id: (v("id") | tonumber? // 0), rawapp: (v("appname") | tostring), app: (v("appname") | clean),
      tag: (v("stack_tag") | tostring), summary: (v("summary") | clean), body: (v("body") | clean),
      ts: (v("timestamp") | tonumber? // 0), icon: (v("icon_path") | tostring),
      critical: (v("urgency") | tostring | ascii_upcase == "CRITICAL")}
   | select(island_shows)]
  | sort_by(-.ts, -.id)'
# Entries -> total NUL entries-JSON NUL icon paths (NUL each).
HISTORY_LOAD_JQ="$HISTORY_ITEMS_JQ"'
  | reduce .[] as $e ({seen: {}, out: []};
      if .seen["i\($e.id)"] or ($e.tag != "" and .seen["k\($e.app)\u001e\($e.tag)"]) then .
      else .seen["i\($e.id)"] = true | .seen["k\($e.app)\u001e\($e.tag)"] = ($e.tag != "") | .out += [$e] end)
  | .out
  | "\(length)\u0000\(tojson)\u0000" + ([.[].icon | select(. != "") + "\u0000"] | unique | add // "")'
# Entry $id -> raw app NUL clean app NUL ids to remove (space separated): the entry and its hidden copies.
HISTORY_TAKE_JQ="$HISTORY_ITEMS_JQ"'
  | (first(.[] | select(.id == $id)) // empty) as $hit
  | "\($hit.rawapp)\u0000\($hit.app)\u0000"
    + ([.[] | select(.id == $id or ($hit.tag != "" and .app == $hit.app and .tag == $hit.tag)) | .id | tostring] | join(" "))'

# history_load: set entries (JSON list), total and icons (the icon paths that exist) from dunst history.
history_load() {
  local -a parts
  local icon
  entries='[]' total=0 icons=()
  mapfile -d '' parts < <(dunstctl history 2>/dev/null | jq -j "$HISTORY_LOAD_JQ" 2>/dev/null)
  [[ ${parts[0]:-} =~ ^[0-9]+$ && -n ${parts[1]:-} ]] || return 0
  # shellcheck disable=SC2034 # the caller's state
  total=${parts[0]} entries=${parts[1]}
  for icon in "${parts[@]:2}"; do [[ -f $icon ]] && icons+=("$icon"); done
}

# history_take ID APP_VAR ENTRY_VAR: drop entry ID and its hidden copies from dunst history, setting
# APP_VAR to its app and ENTRY_VAR to its desktop entry. Fails when the history has no entry ID.
history_take() {
  local -a parts
  local raw desktop id
  mapfile -d '' parts < <(dunstctl history 2>/dev/null | jq -j --argjson id "$1" "$HISTORY_TAKE_JQ" 2>/dev/null)
  (( ${#parts[@]} == 3 )) || return 1
  # notify-hook recorded the desktop entry under its own form of the app name.
  field raw "${parts[0]}" 80
  desktop_lookup desktop "$1" "$raw"
  for id in ${parts[2]}; do dunstctl history-rm "$id" > /dev/null 2>&1; done
  printf -v "$2" '%s' "${parts[1]}"
  printf -v "$3" '%s' "$desktop"
}

# history_clear: empty dunst history and the desktop entry record.
history_clear() {
  dunstctl history-clear > /dev/null 2>&1
  if [[ -f $ISLAND_STATE/notif_entries ]]; then : > "$ISLAND_STATE/notif_entries"; fi
}

# dunst history has no desktop entry, so notify-hook records it in $ISLAND_STATE/notif_entries
# ("ID TAB APP TAB ENTRY", newest last, at most DESKTOP_MAX lines).
DESKTOP_MAX=64

# desktop_remember ID APP ENTRY: record ENTRY for notification ID of APP.
desktop_remember() {
  local file="$ISLAND_STATE/notif_entries" fd lines
  [[ $1 =~ ^[0-9]+$ && -n $3 && -d ${file%/*} ]] || return 0
  exec {fd}>> "$file" || return 0
  flock "$fd" || return 0
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >&"$fd"
  mapfile -t lines < "$file"
  if (( ${#lines[@]} > DESKTOP_MAX )); then
    printf '%s\n' "${lines[@]: -$((DESKTOP_MAX / 2))}" > "$file"
  fi
  exec {fd}>&-
}

# desktop_lookup VAR ID APP: set VAR to the newest entry recorded for ID of APP, else empty.
desktop_lookup() {
  local line_id line_app line_entry found=''
  while IFS=$'\t' read -r line_id line_app line_entry; do
    if [[ $line_id == "$2" && $line_app == "$3" ]]; then found=$line_entry; fi
  done 2>/dev/null < "$ISLAND_STATE/notif_entries"
  printf -v "$1" '%s' "$found"
}
