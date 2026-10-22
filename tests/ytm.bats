# tests/ytm.bats
setup() {
  load helpers
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run" XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  export FAKE="$BATS_TEST_TMPDIR/fake" OB_YTM_HELPER="$BATS_TEST_TMPDIR/bin/like-helper" OB_YTM_RETRY=0.1
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN" "$FAKE/like"
  PATH="$BIN:$PATH"
  STATE="$XDG_RUNTIME_DIR/eww-island"; mkdir -p "$STATE"
  OUT="$BATS_TEST_TMPDIR/out" ERR="$BATS_TEST_TMPDIR/err"
  # ytm status prints $FAKE/status.N files once each in order, then $FAKE/status; ytm queue
  # prints the $FAKE/queue of call time after $FAKE/queue_delay seconds; other subcommands
  # are logged and exit with the code in $FAKE/rc.
  cat > "$BIN/ytm" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$FAKE/ytm.log"
if [[ $1 == queue ]]; then
  q=$(cat "$FAKE/queue" 2>/dev/null) || exit 1
  sleep "$(cat "$FAKE/queue_delay" 2>/dev/null || echo 0)"
  printf '%s\n' "$q"
  exit 0
fi
if [[ $1 == status ]]; then
  for f in "$FAKE"/status.*; do
    [[ -e $f ]] || break
    cat "$f"; rm -f "$f"; exit 0
  done
  cat "$FAKE/status" 2>/dev/null || exit 1
  exit 0
fi
echo "Liked: something"
exit "$(cat "$FAKE/rc" 2>/dev/null || echo 0)"
EOF
  # The like helper answers "$FAKE/like/VID" = "DELAY STATUS".
  cat > "$BIN/like-helper" <<'EOF'
#!/usr/bin/env bash
echo "$1" >> "$FAKE/helper.log"
read -r delay answer < "$FAKE/like/$1" || exit 1
sleep "$delay"
printf '%s\n' "$answer"
EOF
  chmod +x "$BIN/ytm" "$BIN/like-helper"
  source "$SCRIPTS/ytm"
}

teardown() {
  if [[ -n ${LISTENER:-} ]]; then kill "$LISTENER" 2>/dev/null; wait "$LISTENER" 2>/dev/null; fi
  return 0
}

INACTIVE='{"active":false,"video_id":"","like":"","next_title":"","next_artist":""}'

# st VID LIKE [NEXT_TITLE NEXT_ARTIST]: the listener line for an active track.
st() {
  printf '{"active":true,"video_id":"%s","like":"%s","next_title":"%s","next_artist":"%s"}' \
    "$1" "$2" "${3:-}" "${4:-}"
}

# queue INDEX [DELAY] "VID|TITLE|ARTIST"...: what `ytm queue` reports from now on.
queue() {
  local index=$1; shift
  if [[ $1 =~ ^[0-9.]+$ ]]; then printf '%s\n' "$1" > "$FAKE/queue_delay"; shift; fi
  printf '%s\n' "$@" | jq -Rnc --argjson i "$index" \
    '[inputs | split("|") | {video_id: .[0], title: .[1], artist: .[2], likeStatus: null}]
     | {tracks: ., current_index: $i, length: length, repeat: "off", shuffle: false}' > "$FAKE/queue.tmp"
  mv "$FAKE/queue.tmp" "$FAKE/queue"
}

# Q: a queue playing vidA0000001 at index 1 between two other tracks.
Q='{"tracks":[{"video_id":"vidZ0000000","title":"Song Z","artist":"Artist Z"},{"video_id":"vidA0000001","title":"Song A","artist":"Artist A"},{"video_id":"vidB0000002","title":"Song B","artist":"Artist B"}],"current_index":1,"length":3,"repeat":"off","shuffle":false}'

# play PLAYER TITLE [STATE]: write the island player state the way scripts/media does.
play() {
  printf '%s\n' "$1" > "$STATE/player"
  jq -nc --arg p "$1" --arg t "$2" --arg s "${3:-playing}" \
    '{state:$s,player:$p,title:$t,artist:"Artist",art:"",length:200,length_text:"3:20"}' > "$STATE/media.json.tmp"
  mv "$STATE/media.json.tmp" "$STATE/media.json"
}

# ytm_now VID TITLE: what `ytm status` reports from now on.
ytm_now() {
  jq -nc --arg v "$1" --arg t "$2" '{track:{video_id:$v,title:$t,artist:"Artist",likeStatus:null},is_playing:true}' > "$FAKE/status"
}

# answer VID STATUS [DELAY]: what the like helper returns for VID.
answer() { printf '%s %s\n' "${3:-0}" "$2" > "$FAKE/like/$1"; }

start() {
  "$SCRIPTS/ytm" > "$OUT" 2> "$ERR" 3>&- &
  LISTENER=$!
}

# wait_line JSON: wait up to 5 s for the listener to print exactly this line.
wait_line() {
  local i
  for ((i = 0; i < 100; i++)); do
    grep -qxF -- "$1" "$OUT" 2>/dev/null && return 0
    sleep 0.05
  done
  printf 'timed out waiting for %s; got:\n' "$1"; cat "$OUT"
  return 1
}

# wait_last JSON: wait up to 5 s for this to be the listener's latest line.
wait_last() {
  local i
  for ((i = 0; i < 100; i++)); do
    [[ $(tail -n 1 "$OUT" 2>/dev/null) == "$1" ]] && return 0
    sleep 0.05
  done
  printf 'timed out waiting for last line %s; got:\n' "$1"; cat "$OUT"
  return 1
}

@test "ytm_player and its instances count as YouTube Music, other players do not" {
  ytm_is_player ytm_player
  ytm_is_player ytm_player.instance42
  ! ytm_is_player edge.instance1
  ! ytm_is_player ytm_playerx
  ! ytm_is_player ""
}

@test "toggle actions: an active state is undone, anything else is set" {
  run toggle_action like LIKE;           [ "$output" = "unlike INDIFFERENT" ]
  run toggle_action like DISLIKE;        [ "$output" = "like LIKE" ]
  run toggle_action like INDIFFERENT;    [ "$output" = "like LIKE" ]
  run toggle_action like "";             [ "$output" = "like LIKE" ]
  run toggle_action dislike DISLIKE;     [ "$output" = "unlike INDIFFERENT" ]
  run toggle_action dislike LIKE;        [ "$output" = "dislike DISLIKE" ]
  run toggle_action dislike "";          [ "$output" = "dislike DISLIKE" ]
}

@test "a ytm_player track becomes active with its video id, then its like status" {
  ytm_now vidA0000001 'Song A'
  answer vidA0000001 LIKE
  play ytm_player 'Song A'
  start
  wait_line "$(st vidA0000001 LIKE)"
  [ "$(sed -n 1p "$OUT")" = "$INACTIVE" ]
  [ "$(cat "$STATE/ytm.json")" = "$(st vidA0000001 LIKE)" ]
  [ ! -s "$ERR" ]
}

@test "other players stay inactive and never query ytm or its queue" {
  ytm_now vidA0000001 'Song A'
  answer vidA0000001 LIKE
  queue 0 'vidA0000001|Song A|Artist A' 'vidB0000002|Song B|Artist B'
  play edge.instance7 'Song A'
  start
  wait_line "$INACTIVE"
  play edge.instance7 'Song B'
  sleep 0.5
  [ "$(cat "$OUT")" = "$INACTIVE" ]
  [ ! -e "$FAKE/ytm.log" ]
  [ ! -e "$FAKE/helper.log" ]
}

@test "switching away from ytm_player or stopping turns the buttons off" {
  ytm_now vidA0000001 'Song A'
  answer vidA0000001 DISLIKE
  play ytm_player 'Song A'
  start
  wait_line "$(st vidA0000001 DISLIKE)"
  play edge.instance7 'Video'
  wait_last "$INACTIVE"
  [ "$(tail -n 1 "$OUT")" = "$INACTIVE" ]
  play ytm_player 'Song A'
  wait_line "$(st vidA0000001 DISLIKE)"
  printf '\n' > "$STATE/player"
  jq -nc '{state:"none",player:"",title:"",artist:"",art:"",length:0,length_text:"0:00"}' > "$STATE/media.json.tmp"
  mv "$STATE/media.json.tmp" "$STATE/media.json"
  sleep 0.5
  [ "$(tail -n 1 "$OUT")" = "$INACTIVE" ]
}

@test "a slow answer for an older video is never shown, and answers are cached per video" {
  ytm_now vidA0000001 'Song A'
  answer vidA0000001 LIKE 1
  answer vidB0000002 DISLIKE
  play ytm_player 'Song A'
  start
  wait_line "$(st vidA0000001 '')"
  ytm_now vidB0000002 'Song B'
  play ytm_player 'Song B'
  wait_line "$(st vidB0000002 DISLIKE)"
  sleep 1.3
  [ "$(tail -n 1 "$OUT")" = "$(st vidB0000002 DISLIKE)" ]
  ! grep -qF '"video_id":"vidA0000001","like":"LIKE"' "$OUT"
  ytm_now vidA0000001 'Song A'
  play ytm_player 'Song A'
  wait_line "$(st vidA0000001 LIKE)"
  [ "$(grep -c vidA0000001 "$FAKE/helper.log")" -eq 1 ]
  [ "$(grep -c vidB0000002 "$FAKE/helper.log")" -eq 1 ]
}

@test "pausing and resuming the same track neither re-resolves nor re-fetches" {
  ytm_now vidA0000001 'Song A'
  answer vidA0000001 INDIFFERENT
  play ytm_player 'Song A'
  start
  wait_line "$(st vidA0000001 INDIFFERENT)"
  play ytm_player 'Song A' paused
  play ytm_player 'Song A' playing
  sleep 0.5
  [ "$(grep -c '^status' "$FAKE/ytm.log")" -eq 1 ]
  [ "$(wc -l < "$FAKE/helper.log")" -eq 1 ]
}

@test "ytm status lagging behind MPRIS is retried until the titles agree" {
  jq -nc '{track:{video_id:"vidOld00001",title:"Old Song"}}' > "$FAKE/status.1"
  ytm_now vidA0000001 'Song A'
  answer vidOld00001 LIKE
  answer vidA0000001 INDIFFERENT
  play ytm_player 'Song A'
  start
  wait_line "$(st vidA0000001 INDIFFERENT)"
  ! grep -qF vidOld00001 "$OUT"
}

@test "toggle-like on a liked track unlikes it and the listener shows it at once" {
  ytm_now vidA0000001 'Song A'
  answer vidA0000001 LIKE
  play ytm_player 'Song A'
  start
  wait_line "$(st vidA0000001 LIKE)"
  run "$SCRIPTS/ytm" toggle-like
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
  wait_line "$(st vidA0000001 INDIFFERENT)"
  [ "$(grep -vE '^(status|queue)' "$FAKE/ytm.log")" = unlike ]
  run "$SCRIPTS/ytm" toggle-dislike
  wait_line "$(st vidA0000001 DISLIKE)"
  run "$SCRIPTS/ytm" toggle-like
  wait_line "$(st vidA0000001 LIKE)"
  [ "$(grep -vE '^(status|queue)' "$FAKE/ytm.log")" = $'unlike\ndislike\nlike' ]
}

@test "a toggle wins over a like status fetch still in flight" {
  ytm_now vidA0000001 'Song A'
  answer vidA0000001 INDIFFERENT 1
  play ytm_player 'Song A'
  start
  wait_line "$(st vidA0000001 '')"
  run "$SCRIPTS/ytm" toggle-like
  wait_line "$(st vidA0000001 LIKE)"
  sleep 1.3
  [ "$(tail -n 1 "$OUT")" = "$(st vidA0000001 LIKE)" ]
}

@test "a failed ytm command leaves the state untouched" {
  printf '{"active":true,"video_id":"vidA0000001","like":"LIKE"}\n' > "$STATE/ytm.json"
  echo 1 > "$FAKE/rc"
  run "$SCRIPTS/ytm" toggle-like
  [ "$status" -ne 0 ]
  [ ! -e "$STATE/ytm_set" ]
  [ "$(cat "$FAKE/ytm.log")" = unlike ]
}

@test "toggles do nothing while inactive" {
  printf '%s\n' "$INACTIVE" > "$STATE/ytm.json"
  run "$SCRIPTS/ytm" toggle-like
  [ "$status" -eq 0 ]
  run "$SCRIPTS/ytm" toggle-dislike
  [ "$status" -eq 0 ]
  [ ! -e "$FAKE/ytm.log" ]
  rm -f "$STATE/ytm.json"
  run "$SCRIPTS/ytm" toggle-like
  [ "$status" -eq 0 ]
  [ ! -e "$FAKE/ytm.log" ]
}

@test "without the ytm CLI the listener stays inactive and quiet" {
  export OB_YTM_CLI=ytm-not-installed
  play ytm_player 'Song A'
  run timeout 1 "$SCRIPTS/ytm"
  [ "$output" = "$INACTIVE" ]
  run "$SCRIPTS/ytm" toggle-like
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "without ytmusicapi or auth the listener goes inactive and stops asking" {
  ytm_now vidA0000001 'Song A'
  answer vidA0000001 UNAVAILABLE
  answer vidB0000002 UNAVAILABLE
  play ytm_player 'Song A'
  start
  wait_line "$(st vidA0000001 '')"
  sleep 0.5
  [ "$(tail -n 1 "$OUT")" = "$INACTIVE" ]
  ytm_now vidB0000002 'Song B'
  play ytm_player 'Song B'
  sleep 0.5
  [ "$(tail -n 1 "$OUT")" = "$INACTIVE" ]
  [ "$(wc -l < "$FAKE/helper.log")" -eq 1 ]
  [ ! -s "$ERR" ]
}

@test "a failed fetch shows no status and is retried when the track comes back" {
  ytm_now vidA0000001 'Song A'
  play ytm_player 'Song A'
  start
  wait_line "$(st vidA0000001 '')"
  sleep 0.3
  ytm_now vidB0000002 'Song B'
  answer vidB0000002 LIKE
  play ytm_player 'Song B'
  wait_line "$(st vidB0000002 LIKE)"
  answer vidA0000001 DISLIKE
  ytm_now vidA0000001 'Song A'
  play ytm_player 'Song A'
  wait_line "$(st vidA0000001 DISLIKE)"
  [ ! -s "$ERR" ]
}

@test "titles with quotes, backslashes and newlines match ytm status at the first try" {
  title=$'Say "Hi" \\ now\nPart two'
  ytm_now vidA0000001 "$title"
  answer vidA0000001 LIKE
  play ytm_player "$title"
  start
  wait_line "$(st vidA0000001 LIKE)"
  [ "$(grep -c '^status' "$FAKE/ytm.log")" -eq 1 ]
}

@test "next_track: the entry after the current index of the playing video" {
  run next_track vidA0000001 <<< "$Q"
  [ "$output" = $'"Song B"\t"Artist B"' ]
}

@test "next_track: nothing after the last entry, or when the current video is missing" {
  run next_track vidB0000002 <<< "$(jq -c '.current_index = 2' <<< "$Q")"
  [ "$output" = $'""\t""' ]
  run next_track vidX0000009 <<< "$Q"
  [ "$output" = $'""\t""' ]
  # The queue still names another track as current: no guess from a later occurrence.
  run next_track vidZ0000000 <<< "$Q"
  [ "$output" = $'""\t""' ]
  run next_track vidA0000001 <<< '{"tracks":[],"current_index":-1}'
  [ "$output" = $'""\t""' ]
  run next_track vidA0000001 <<< 'not json'
  [ "$output" = $'""\t""' ]
}

@test "next_track: follows repeat and shuffle like the player does" {
  run next_track vidA0000001 <<< "$(jq -c '.repeat = "one"' <<< "$Q")"
  [ "$output" = $'"Song A"\t"Artist A"' ]
  run next_track vidB0000002 <<< "$(jq -c '.current_index = 2 | .repeat = "all"' <<< "$Q")"
  [ "$output" = $'"Song Z"\t"Artist Z"' ]
  # The player reshuffles at the end of a shuffled repeat-all queue: nothing to predict.
  run next_track vidB0000002 <<< "$(jq -c '.current_index = 2 | .repeat = "all" | .shuffle = true' <<< "$Q")"
  [ "$output" = $'""\t""' ]
  run next_track vidA0000001 <<< "$(jq -c 'del(.current_index)' <<< "$Q")"
  [ "$output" = $'"Song B"\t"Artist B"' ]
}

@test "next_track: quotes, backslashes, tabs and newlines stay on one JSON-escaped line" {
  run next_track vidA0000001 <<< "$(jq -c '.tracks[2].title = "Say \"Hi\" \\ now\tand\nthen" | .tracks[2].artist = null' <<< "$Q")"
  [ "$output" = $'"Say \\"Hi\\" \\\\ now\\tand\\nthen"\t""' ]
}

@test "the next track of the ytm queue is shown with the playing one" {
  ytm_now vidA0000001 'Song A'
  answer vidA0000001 LIKE
  queue 1 'vidZ0000000|Song Z|Artist Z' 'vidA0000001|Song A|Artist A' 'vidB0000002|Song B|Artist B'
  play ytm_player 'Song A'
  start
  wait_line "$(st vidA0000001 LIKE 'Song B' 'Artist B')"
  [ "$(cat "$STATE/ytm.json")" = "$(st vidA0000001 LIKE 'Song B' 'Artist B')" ]
  [ "$(grep -c '^queue' "$FAKE/ytm.log")" -eq 1 ]
  [ ! -s "$ERR" ]
}

@test "the last track of the queue, or one missing from it, has no next track" {
  ytm_now vidB0000002 'Song B'
  answer vidB0000002 LIKE
  queue 1 'vidA0000001|Song A|Artist A' 'vidB0000002|Song B|Artist B'
  play ytm_player 'Song B'
  start
  wait_line "$(st vidB0000002 LIKE)"
  sleep 0.5
  [ "$(tail -n 1 "$OUT")" = "$(st vidB0000002 LIKE)" ]
  [ "$(grep -c '^queue' "$FAKE/ytm.log")" -eq 1 ]
  ytm_now vidC0000003 'Song C'
  answer vidC0000003 INDIFFERENT
  play ytm_player 'Song C'
  wait_line "$(st vidC0000003 INDIFFERENT)"
  sleep 0.5
  [ "$(tail -n 1 "$OUT")" = "$(st vidC0000003 INDIFFERENT)" ]
  [ "$(grep -c '^queue' "$FAKE/ytm.log")" -eq 2 ]
  [ "$(grep -c '"next_title":"Song' "$OUT")" -eq 0 ]
}

@test "a slow queue answer for an older track is never shown, and a new track clears the old next" {
  ytm_now vidA0000001 'Song A'
  answer vidA0000001 LIKE
  answer vidB0000002 DISLIKE
  queue 0 'vidA0000001|Song A|Artist A' 'vidX0000009|Old Next|Artist X'
  echo 1 > "$FAKE/queue_delay"
  play ytm_player 'Song A'
  start
  wait_line "$(st vidA0000001 LIKE)"
  # Let the slow call read the old queue before it changes.
  for ((i = 0; i < 100; i++)); do grep -q '^queue' "$FAKE/ytm.log" 2>/dev/null && break; sleep 0.05; done
  sleep 0.2
  queue 0 0 'vidB0000002|Song B|Artist B' 'vidY0000008|New Next|Artist Y'
  ytm_now vidB0000002 'Song B'
  play ytm_player 'Song B'
  wait_line "$(st vidB0000002 DISLIKE 'New Next' 'Artist Y')"
  sleep 1.3
  [ "$(tail -n 1 "$OUT")" = "$(st vidB0000002 DISLIKE 'New Next' 'Artist Y')" ]
  [ "$(grep -c 'Old Next' "$OUT")" -eq 0 ]
  # A new track drops the previous next at once, before its own queue answer.
  answer vidY0000008 LIKE
  queue 1 0.5 'vidB0000002|Song B|Artist B' 'vidY0000008|New Next|Artist Y' 'vidW0000007|Last|Artist W'
  ytm_now vidY0000008 'New Next'
  play ytm_player 'New Next'
  wait_line "$(st vidY0000008 LIKE)"
  wait_line "$(st vidY0000008 LIKE 'Last' 'Artist W')"
}

@test "switching away from ytm_player clears the next track" {
  ytm_now vidA0000001 'Song A'
  answer vidA0000001 LIKE
  queue 0 'vidA0000001|Song A|Artist A' 'vidB0000002|Song B|Artist B'
  play ytm_player 'Song A'
  start
  wait_line "$(st vidA0000001 LIKE 'Song B' 'Artist B')"
  play edge.instance7 'Video'
  wait_last "$INACTIVE"
  [ "$(tail -n 1 "$OUT")" = "$INACTIVE" ]
  [ "$(jq -r '.next_title + .next_artist' "$STATE/ytm.json")" = "" ]
}
