#!/usr/bin/env bash
# Alert source: meeting reminders from the agenda. Its monitor, scripts/agenda watch, also keeps
# $ISLAND_STATE/agenda.json fresh for the Kalender tab. Source it; do not execute.
# shellcheck source=../store.sh
source "$DIR/lib/store.sh"
# shellcheck source=../todo/data.sh
source "$DIR/lib/todo/data.sh"
MEETING_FILE="$ISLAND_STATE/agenda.json"
MEETING_FIRED="$ISLAND_STATE/meeting-alerts"
# Due reminders as "row<TAB>key<TAB>start": soon from $before seconds ahead, start from the start
# time until five minutes in.
# shellcheck disable=SC2016 # jq variables
MEETING_DUE_JQ='(.rows // []) | to_entries[] | .key as $i | .value | select(.start + 300 > $now)
  | if $now >= .start then [$i, "start", .start]
    elif $before > 0 and $now >= .start - $before then [$i, "soon", .start]
    else empty end | @tsv'

# Prep suffix for a row id against a Tugas document: empty when the row has no prep items or all
# of them are done.
# shellcheck disable=SC2016 # jq variables
MEETING_PREP_JQ='[.items[]? | select(.prep == $id)] as $items
  | if ($items | length) == 0 or (([$items[] | select(.done | not)] | length) == 0) then ""
    else " · Prep \([$items[] | select(.done)] | length)/\($items | length) belum selesai" end'

# meeting_body TITLE ID TODO_DOC: TITLE with the prep suffix when ID has unfinished prep items.
meeting_body() {
  local suffix
  suffix=$(jq -r --arg id "$2" "$MEETING_PREP_JQ" <<< "$3" 2>/dev/null) || suffix=''
  printf '%s%s' "$1" "$suffix"
}

meeting_init() {
  alert_need notify-send python3 || return
  [[ -f ${ISLAND_CALENDARS:-${XDG_CONFIG_HOME:-$HOME/.config}/openbox-island/calendars} ]] \
    || alert_skip 'config kalender belum ada'
}
meeting_monitor() { printf '%s\0' "$DIR/agenda" watch; }
meeting_event() { meeting_remind; }

# This source keeps no sampled state, so its baseline has nothing to do.
meeting_snapshot() { :; }

# meeting_open SECONDS: show the Kalender tab on the island for SECONDS.
meeting_open() { "$DIR/island" auto "$1" kalender > /dev/null 2>&1 || :; }

# meeting_claim ID KEY: record the reminder as sent; fails when it, or the start, already was, so a
# late wake-up shows only the start.
meeting_claim() {
  local fd rc=0
  exec {fd}>> "$MEETING_FIRED.lock" || return 1
  flock "$fd"
  if grep -qxF -e "$1 $2" -e "$1 start" "$MEETING_FIRED" 2> /dev/null; then rc=1
  elif ! printf '%s %s\n' "$1" "$2" >> "$MEETING_FIRED"; then rc=1; fi
  exec {fd}>&-
  return "$rc"
}

# meeting_remind: notify each meeting reminder now due, once, and open the Kalender tab.
meeting_remind() {
  local now before doc todo row key start id title line
  now=${ISLAND_NOW:-$EPOCHSECONDS}
  before=${ISLAND_MEETING_BEFORE-10}
  [[ $before =~ ^[0-9]+$ ]] || before=0
  doc=$(cat "$MEETING_FILE" 2> /dev/null) || return 0
  todo=$(store_read "$TODO_FILE" "$TODO_EMPTY")
  while IFS=$'\t' read -r row key start; do
    id=$(jq -r --argjson i "$row" '.rows[$i].id' <<< "$doc")
    meeting_claim "$id" "$key" || continue
    title=$(jq -r --argjson i "$row" '.rows[$i].title' <<< "$doc")
    if [[ $key == soon ]]; then
      line="Meeting $(( (start - now + 59) / 60 )) menit lagi · $(date -d "@$start" +%H:%M)"
    else
      line="Meeting dimulai · $(date -d "@$start" +%H:%M)"
    fi
    notify-send -a Kalender -- "$line" "$(meeting_body "$title" "$id" "$todo")" || :
    meeting_open "${ISLAND_MEETING_AUTO:-10}"
  done < <(jq -r --argjson now "$now" --argjson before "$((before * 60))" "$MEETING_DUE_JQ" <<< "$doc" 2> /dev/null)
}
