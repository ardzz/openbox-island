# tests/ytm.bats
setup() {
  load helpers
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run" XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  export FAKE="$BATS_TEST_TMPDIR/fake" OB_YTM_HELPER="$BATS_TEST_TMPDIR/bin/like-helper" OB_YTM_RETRY=0.1
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN" "$FAKE/like"
  PATH="$BIN:$PATH"
  STATE="$XDG_RUNTIME_DIR/eww-island"; mkdir -p "$STATE"
  OUT="$BATS_TEST_TMPDIR/out" ERR="$BATS_TEST_TMPDIR/err"
  # ytm status prints $FAKE/status.N files once each in order, then $FAKE/status; other
  # subcommands are logged and exit with the code in $FAKE/rc.
  cat > "$BIN/ytm" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$FAKE/ytm.log"
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

INACTIVE='{"active":false,"video_id":"","like":""}'

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
  wait_line '{"active":true,"video_id":"vidA0000001","like":"LIKE"}'
  [ "$(sed -n 1p "$OUT")" = "$INACTIVE" ]
  [ "$(cat "$STATE/ytm.json")" = '{"active":true,"video_id":"vidA0000001","like":"LIKE"}' ]
  [ ! -s "$ERR" ]
}

@test "other players stay inactive and never query ytm" {
  ytm_now vidA0000001 'Song A'
  answer vidA0000001 LIKE
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
  wait_line '{"active":true,"video_id":"vidA0000001","like":"DISLIKE"}'
  play edge.instance7 'Video'
  wait_line "$INACTIVE"
  [ "$(tail -n 1 "$OUT")" = "$INACTIVE" ]
  play ytm_player 'Song A'
  wait_line '{"active":true,"video_id":"vidA0000001","like":"DISLIKE"}'
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
  wait_line '{"active":true,"video_id":"vidA0000001","like":""}'
  ytm_now vidB0000002 'Song B'
  play ytm_player 'Song B'
  wait_line '{"active":true,"video_id":"vidB0000002","like":"DISLIKE"}'
  sleep 1.3
  [ "$(tail -n 1 "$OUT")" = '{"active":true,"video_id":"vidB0000002","like":"DISLIKE"}' ]
  ! grep -qF '"video_id":"vidA0000001","like":"LIKE"' "$OUT"
  ytm_now vidA0000001 'Song A'
  play ytm_player 'Song A'
  wait_line '{"active":true,"video_id":"vidA0000001","like":"LIKE"}'
  [ "$(grep -c vidA0000001 "$FAKE/helper.log")" -eq 1 ]
  [ "$(grep -c vidB0000002 "$FAKE/helper.log")" -eq 1 ]
}

@test "pausing and resuming the same track neither re-resolves nor re-fetches" {
  ytm_now vidA0000001 'Song A'
  answer vidA0000001 INDIFFERENT
  play ytm_player 'Song A'
  start
  wait_line '{"active":true,"video_id":"vidA0000001","like":"INDIFFERENT"}'
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
  wait_line '{"active":true,"video_id":"vidA0000001","like":"INDIFFERENT"}'
  ! grep -qF vidOld00001 "$OUT"
}

@test "toggle-like on a liked track unlikes it and the listener shows it at once" {
  ytm_now vidA0000001 'Song A'
  answer vidA0000001 LIKE
  play ytm_player 'Song A'
  start
  wait_line '{"active":true,"video_id":"vidA0000001","like":"LIKE"}'
  run "$SCRIPTS/ytm" toggle-like
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
  wait_line '{"active":true,"video_id":"vidA0000001","like":"INDIFFERENT"}'
  [ "$(grep -v '^status' "$FAKE/ytm.log")" = unlike ]
  run "$SCRIPTS/ytm" toggle-dislike
  wait_line '{"active":true,"video_id":"vidA0000001","like":"DISLIKE"}'
  run "$SCRIPTS/ytm" toggle-like
  wait_line '{"active":true,"video_id":"vidA0000001","like":"LIKE"}'
  [ "$(grep -v '^status' "$FAKE/ytm.log")" = $'unlike\ndislike\nlike' ]
}

@test "a toggle wins over a like status fetch still in flight" {
  ytm_now vidA0000001 'Song A'
  answer vidA0000001 INDIFFERENT 1
  play ytm_player 'Song A'
  start
  wait_line '{"active":true,"video_id":"vidA0000001","like":""}'
  run "$SCRIPTS/ytm" toggle-like
  wait_line '{"active":true,"video_id":"vidA0000001","like":"LIKE"}'
  sleep 1.3
  [ "$(tail -n 1 "$OUT")" = '{"active":true,"video_id":"vidA0000001","like":"LIKE"}' ]
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
  wait_line '{"active":true,"video_id":"vidA0000001","like":""}'
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
  wait_line '{"active":true,"video_id":"vidA0000001","like":""}'
  sleep 0.3
  ytm_now vidB0000002 'Song B'
  answer vidB0000002 LIKE
  play ytm_player 'Song B'
  wait_line '{"active":true,"video_id":"vidB0000002","like":"LIKE"}'
  answer vidA0000001 DISLIKE
  ytm_now vidA0000001 'Song A'
  play ytm_player 'Song A'
  wait_line '{"active":true,"video_id":"vidA0000001","like":"DISLIKE"}'
  [ ! -s "$ERR" ]
}

@test "titles with quotes, backslashes and newlines match ytm status at the first try" {
  title=$'Say "Hi" \\ now\nPart two'
  ytm_now vidA0000001 "$title"
  answer vidA0000001 LIKE
  play ytm_player "$title"
  start
  wait_line '{"active":true,"video_id":"vidA0000001","like":"LIKE"}'
  [ "$(grep -c '^status' "$FAKE/ytm.log")" -eq 1 ]
}
