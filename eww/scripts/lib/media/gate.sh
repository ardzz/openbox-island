#!/usr/bin/env bash
# YouTube Music identity and fresh browser bridge proof for media records.

norm_title() {
  jq -Rrs 'ascii_downcase | gsub("[^[:alnum:][:space:]]"; "") |
    gsub("[[:space:]]+"; " ") | sub("^ "; "") | sub(" $"; "")' <<<"$1"
}

gate_player_ok() {
  local bridge ts title expected now
  case $1 in
    ytm_player|ytm_player.*|ytermusic|ytermusic.*) return 0 ;;
    edge|edge.*) ;;
    *) return 1 ;;
  esac
  bridge=$(cat "$ISLAND_STATE/ytm-browser.json" 2>/dev/null) || return 1
  ts=$(jq -er '.ts | select(type == "number" and floor == .)' <<<"$bridge" 2>/dev/null) || return 1
  now=$(( ${EPOCHREALTIME/./} / 1000 ))
  (( now - ts <= 15000 )) || return 1
  title=$(jq -er '.title | select(type == "string")' <<<"$bridge" 2>/dev/null) || return 1
  title=$(norm_title "$title")
  expected=$(norm_title "$2")
  if [[ -n $expected && $title == "$expected" ]]; then
    GATE_LAST_MATCH_MS=$now
    return 0
  fi
  [[ -n $expected && -n $title ]] && (( ${GATE_LAST_MATCH_MS:-0} > 0 && now - GATE_LAST_MATCH_MS <= 5000 ))
}

# Filter in the caller's shell so the last matching timestamp survives each record.
gate_record() {
  local -n filtered=$1
  local player title
  IFS=$SEP read -r -d '' _ player title _ < <(printf '%s' "$filtered")
  gate_player_ok "$player" "$title" || filtered=""
  return 0
}
