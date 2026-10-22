#!/usr/bin/env bash
# Background queries of the ytm listener. Each job prints one tab-separated event line:
# "vid GEN VID", "like VID STATUS" or "next GEN TITLE_JSON ARTIST_JSON". Source it after core.sh.

# resolve_job GEN TITLE_JSON: video id of the playing track; retried while `ytm status` still names another title.
resolve_job() {
  local gen=$1 title=$2 attempt vid now
  for attempt in 1 2 3 4; do
    IFS=$'\t' read -r now vid < <(timeout 3 "$YTM" status 2>/dev/null |
      jq -r '(.track.title // "" | tojson) + "\t" + (.track.video_id // "")' 2>/dev/null)
    [[ $now == "$title" ]] && break
    (( attempt < 4 )) && sleep "$RETRY"
  done
  printf 'vid\t%s\t%s\n' "$gen" "$vid"
}

# like_job VID: the helper's answer; an unrunnable helper counts as unavailable.
like_job() {
  local answer rc
  answer=$(timeout 20 "$HELPER" "$1" 2>/dev/null)
  rc=$?
  (( rc == 126 || rc == 127 )) && answer=UNAVAILABLE
  printf 'like\t%s\t%s\n' "$1" "${answer%%$'\n'*}"
}

# next_track VID: `ytm queue` JSON on stdin -> JSON-encoded "title"<TAB>"artist" of the track after VID,
# chosen like ytm-player's own peek; "" "" when the queue's current entry is not VID or nothing follows.
next_track() {
  local next
  next=$(jq -r --arg vid "$1" '
    (.tracks // []) as $t
    | (if (.current_index | type) == "number" then .current_index
       else [$t[].video_id] | index($vid) end) as $i
    | if $i == null or $i < 0 or $t[$i].video_id != $vid then null
      elif .repeat == "one" then $t[$i]
      elif $i + 1 < ($t | length) then $t[$i + 1]
      elif .repeat == "all" and (.shuffle | not) then $t[0]
      else null end
    | [.title // "", .artist // ""] | map(tostring | tojson) | join("\t")' 2>/dev/null)
  next=${next%%$'\n'*}
  [[ -n $next ]] || next=$'""\t""'
  printf '%s\n' "$next"
}

# queue_job GEN VID: the next track after VID in the ytm-player queue.
queue_job() {
  local next
  next=$(timeout 3 "$YTM" queue 2>/dev/null | next_track "$2")
  printf 'next\t%s\t%s\n' "$1" "$next"
}
