# tests/ytm/like.bats: the ytm listener: active state, video id and like status
load common

@test "ytm_player and its instances count as YouTube Music, other players do not" {
  ytm_is_player ytm_player
  ytm_is_player ytm_player.instance42
  ! ytm_is_player edge.instance1
  ! ytm_is_player ytm_playerx
  ! ytm_is_player ""
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
