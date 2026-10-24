#!/usr/bin/env bash
# Create Tugas prep items before meetings matching a template, once per occurrence.
# Source it after core.sh, store.sh, lib/todo/data.sh, lib/todo/deadline.sh and
# lib/prep/template.sh; do not execute.
PREP_LEDGER="${XDG_DATA_HOME:-$HOME/.local/share}/eww-island/prep-made"

# One Tugas item per entry of $new ({text, prep}), ids continuing from next_id.
PREP_ADD_JQ='.next_id as $base
  | .items += [range(0; ($new | length)) as $i | $new[$i]
      + {id: ($base + $i), done: false, created: $created, due: $due, reminded: $reminded}]
  | .next_id = $base + ($new | length)'

# prep_ledger_has ID: the ledger already records ID.
prep_ledger_has() {
  [[ -r $PREP_LEDGER ]] || return 1
  local id start
  while read -r id start; do [[ $id == "$1" ]] && return 0; done < "$PREP_LEDGER"
  return 1
}

# prep_ledger_write NOW [ID START]: rewrite the ledger keeping lines whose START
# is at most 7 days before NOW (plus the optional new line), atomically.
prep_ledger_write() {
  local now=$1 id start tmp kept=()
  if [[ -r $PREP_LEDGER ]]; then
    while read -r id start; do
      [[ $start =~ ^[0-9]+$ ]] || continue
      (( start >= now - 7 * 86400 )) && kept+=("$id $start")
    done < "$PREP_LEDGER"
  fi
  (( $# >= 3 )) && kept+=("$2 $3")
  mkdir -p -- "${PREP_LEDGER%/*}" || return 1
  tmp=$(mktemp "${PREP_LEDGER}.XXXXXX") || return 1
  if (( ${#kept[@]} )); then
    printf '%s\n' "${kept[@]}" > "$tmp" || { rm -f -- "$tmp"; return 1; }
  else
    : > "$tmp" || { rm -f -- "$tmp"; return 1; }
  fi
  mv -f -- "$tmp" "$PREP_LEDGER"
}

# prep_sync_row ID START TITLE NOW: add the template items for one row and record
# it; no matching template is a no-op, a failed add records nothing and fails.
prep_sync_row() {
  local id=$1 start=$2 title=$3 now=$4
  local tmpl before items due reminded new
  tmpl=$(prep_match "$title") || return 0
  before=$(jq -r '.before' <<< "$tmpl") || return 1
  items=$(jq -c '.items' <<< "$tmpl") || return 1
  due=$(prep_due "$start" "$before") || return 1
  (( due > now )) || due=$start
  reminded=$(deadline_passed_keys "$due" "$now") || return 1
  new=$(jq -cn --arg title "$title" --argjson items "$items" --arg prep "$id" \
    --argjson max "$MAX_TEXT" \
    '[ $items[] | (($title + " · " + .) as $t | {text: ('"$TEXT_JQ"'), prep: $prep}) ]') || return 1
  todo_change "$PREP_ADD_JQ" --argjson new "$new" --argjson created "${now}000000" \
    --argjson due "$due" --argjson reminded "$reminded" || return 1
  prep_ledger_write "$now" "$id" "$start"
}

# prep_sync_locked NOW AHEAD: create items for agenda rows in the window.
prep_sync_locked() {
  local now=$1 ahead=$2 doc row id start title
  doc=$(cat "$ISLAND_STATE/agenda.json" 2>/dev/null) || return 0
  while IFS= read -r row; do
    [[ -n $row ]] || continue
    id=$(jq -r '.id' <<< "$row") || return 1
    start=$(jq -r '.start' <<< "$row") || return 1
    title=$(jq -r '.title' <<< "$row") || return 1
    prep_ledger_has "$id" && continue
    prep_sync_row "$id" "$start" "$title" "$now" || return 1
  done < <(jq -c --argjson now "$now" --argjson until "$((now + ahead * 3600))" \
    'if .ok == true then (.rows // [])[] | select(.start > $now and .start <= $until)
     else empty end' <<< "$doc" 2>/dev/null)
  return 0
}

# prep_sync: create prep items for matching meetings starting within
# ISLAND_PREP_AHEAD hours (default 24; set-but-empty disables). The whole
# check-add-record runs under the ledger lock; each ledger write prunes stale lines.
prep_sync() {
  if [[ -v ISLAND_PREP_AHEAD && -z $ISLAND_PREP_AHEAD ]]; then return 0; fi
  local ahead=${ISLAND_PREP_AHEAD:-24} now fd rc=0
  [[ $ahead =~ ^[0-9]+$ ]] || ahead=24
  now=$(todo_now)
  mkdir -p -- "${PREP_LEDGER%/*}" || return 1
  exec {fd}> "${PREP_LEDGER}.lock" || return 1
  if flock "$fd"; then
    prep_sync_locked "$now" "$ahead" || rc=$?
  else
    rc=1
  fi
  exec {fd}>&-
  return "$rc"
}
