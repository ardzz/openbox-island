# tests/ytm/toggle.bats: ytm toggle-like and toggle-dislike
load common

@test "toggle actions: an active state is undone, anything else is set" {
  run toggle_action like LIKE;           [ "$output" = "unlike INDIFFERENT" ]
  run toggle_action like DISLIKE;        [ "$output" = "like LIKE" ]
  run toggle_action like INDIFFERENT;    [ "$output" = "like LIKE" ]
  run toggle_action like "";             [ "$output" = "like LIKE" ]
  run toggle_action dislike DISLIKE;     [ "$output" = "unlike INDIFFERENT" ]
  run toggle_action dislike LIKE;        [ "$output" = "dislike DISLIKE" ]
  run toggle_action dislike "";          [ "$output" = "dislike DISLIKE" ]
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
