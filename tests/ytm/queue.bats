# tests/ytm/queue.bats: the next track from the ytm queue
load common

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
