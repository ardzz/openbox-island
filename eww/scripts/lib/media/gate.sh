#!/usr/bin/env bash
# YouTube Music identity and fresh browser bridge proof for media records.

norm_title() {
  local title=${1,,} char normalized="" space=""
  while IFS= read -r -N 1 char; do
    case $char in
      [[:alnum:]]) normalized+=$space$char; space="" ;;
      [[:space:]]) [[ -z $normalized ]] || space=" " ;;
    esac
  done < <(printf '%s' "$title")
  printf '%s\n' "$normalized"
}

gate_player_ok() {
  local bridge ts title expected now expiry
  case $1 in
    ytm_player|ytm_player.*|ytermusic|ytermusic.*) return 0 ;;
    edge|edge.*) ;;
    *) return 1 ;;
  esac
  bridge=$(cat "$ISLAND_STATE/ytm-browser.json" 2>/dev/null) || return 1
  ts=$(jq -er '.ts | select(type == "number" and floor == .)' <<<"$bridge" 2>/dev/null) || return 1
  now=$(( ${EPOCHREALTIME/./} / 1000 ))
  (( now - ts <= ${ISLAND_BRIDGE_MAX_AGE_MS:-15000} )) || return 1
  expiry=$(( ts + ${ISLAND_BRIDGE_MAX_AGE_MS:-15000} + 1 ))
  title=$(jq -er '.title | select(type == "string")' <<<"$bridge" 2>/dev/null) || return 1
  title=$(norm_title "$title")
  expected=$(norm_title "$2")
  if [[ -n $expected && $title == "$expected" ]]; then
    GATE_LAST_MATCH_MS=$now
    GATE_DEADLINE_MS=$expiry
    return 0
  fi
  [[ -n $expected && -n $title ]] &&
    (( ${GATE_LAST_MATCH_MS:-0} > 0 && now - GATE_LAST_MATCH_MS <= ${ISLAND_BRIDGE_SKEW_MS:-5000} )) || return 1
  GATE_DEADLINE_MS=$(( GATE_LAST_MATCH_MS + ${ISLAND_BRIDGE_SKEW_MS:-5000} + 1 ))
  (( expiry >= GATE_DEADLINE_MS )) || GATE_DEADLINE_MS=$expiry
}

# Filter in the caller's shell so the last matching timestamp survives each record.
gate_record() {
  local -n filtered=$1
  local player title
  GATE_CANDIDATE=""
  [[ -n $filtered ]] || return 0
  GATE_DEADLINE_MS=0
  IFS=$SEP read -r -d '' _ player title _ < <(printf '%s' "$filtered")
  if ! gate_player_ok "$player" "$title"; then
    # shellcheck disable=SC2034 # Consumed by media's timed-read loop.
    case $player in
      edge|edge.*) has_track "$filtered" && GATE_CANDIDATE=$filtered ;;
    esac
    filtered=""
    return 1
  fi
}
