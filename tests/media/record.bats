# tests/media/record.bats: playerctl records becoming island JSON, track keys and island actions
load common

@test "a playing track becomes island JSON with whole seconds and a decoded cover path" {
  touch "$BATS_TEST_TMPDIR/a b.png"
  run media_json "$(line Playing edge.instance11487 'Heroes Tonight' 'Janji, Johnning' "file://$BATS_TEST_TMPDIR/a%20b.png" 290366666)"
  [ "$status" -eq 0 ]
  [ "$(jq -r .art <<<"$output")" = "$BATS_TEST_TMPDIR/a b.png" ]
  [ "$(jq -c 'del(.art)' <<<"$output")" = '{"state":"playing","player":"edge.instance11487","title":"Heroes Tonight","artist":"Janji, Johnning","length":290,"length_text":"4:50"}' ]
}

@test "paused keeps the track; stopped and an empty line mean no player" {
  none='{"state":"none","player":"","title":"","artist":"","art":"","length":0,"length_text":"0:00"}'
  run media_json "$(line Paused edge.i1 T A '' 1000000)"
  [ "$(jq -c '[.state,.title]' <<<"$output")" = '["paused","T"]' ]
  run media_json "$(line Stopped edge.i1 T A '' 1000000)"
  [ "$output" = "$none" ]
  run media_json ""
  [ "$output" = "$none" ]
}

@test "quotes and backslashes in titles survive into JSON" {
  run media_json "$(line Playing edge.i1 'Say "Hi" \ now' A '' 0)"
  [ "$(jq -r .title <<<"$output")" = 'Say "Hi" \ now' ]
}

@test "embedded newlines in titles preserve the remaining metadata" {
  run media_json "$(line Playing edge.i1 $'Part one\nPart two' A '' 0)"
  [ "$(jq -r .title <<<"$output")" = $'Part one\nPart two' ]
  [ "$(jq -r .artist <<<"$output")" = A ]
  [ "$(jq -r .length <<<"$output")" = 0 ]
}

@test "missing length and unsupported cover schemes fall back to zero and no cover" {
  run media_json "$(line Playing edge.i1 T A 'data:image/png;base64,AAAA' '')"
  [ "$(jq -c '[.art,.length,.length_text]' <<<"$output")" = '["",0,"0:00"]' ]
}

@test "track_key names player, title and artist; nothing when stopped" {
  run track_key "$(line Playing edge.i1 T A file:///x 5)"; [ "$output" = "$(line edge.i1 T A)" ]
  run track_key "$(line Paused edge.i1 T A '' 5)";       [ "$output" = "$(line edge.i1 T A)" ]
  run track_key "$(line Stopped edge.i1 T A '' 5)";      [ "$output" = "" ]
  run track_key "";                                      [ "$output" = "" ]
}

@test "only a new playing track auto-expands, never the first update" {
  run media_action 1 "" k1 Playing;  [ "$output" = none ]
  run media_action 0 k1 k2 Playing;  [ "$output" = auto ]
  run media_action 0 k1 k1 Playing;  [ "$output" = none ]
  run media_action 0 k1 k2 Paused;   [ "$output" = none ]
}

@test "the island closes only when a shown player disappears" {
  run media_action 0 k1 "" "";  [ "$output" = close ]
  run media_action 1 "" "" "";  [ "$output" = none ]
}

@test "loading_json keeps the player but no track details" {
  run loading_json edge.i1
  [ "$output" = '{"state":"loading","player":"edge.i1","title":"","artist":"","art":"","length":0,"length_text":"0:00"}' ]
}
