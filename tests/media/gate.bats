# tests/media/gate.bats: only YouTube Music records may drive the island.
load common

bridge() {
  mkdir -p "$STATE"
  jq -nc --arg title "$1" --argjson ts "${2:-$(date +%s%3N)}" \
    '{title:$title,artist:"X",album:"",video_id:"id",playing:true,ts:$ts}' > "$STATE/ytm-browser.json"
}

listen_track() {
  listener "printf 'Playing\\x1f$1\\x1f$2\\x1fX\\x1f\\x1f1000000\\x1e\\n'"
  run bash -c 'source "$1"; stream | emit_dedup' _ "$BATS_TEST_TMPDIR/eww/scripts/media"
  [ "$status" -eq 0 ]
}

assert_blocked() {
  [ "$output" = "$NONE_JSON" ]
  [ "$(cat "$STATE/player")" = "" ]
  [ ! -s "$BATS_TEST_TMPDIR/island.log" ]
}

@test "Edge without a bridge is none and never opens the island" {
  listen_track edge.i1 A
  assert_blocked
}

@test "Edge accepts only an exact normalized title from a fresh bridge" {
  bridge 'hELLo,   WORLD!'
  listen_track edge.i1 'Hello World'
  [ "${#lines[@]}" -eq 2 ]
  [ "$(jq -r '.state + ":" + .title' <<<"${lines[1]}")" = 'playing:Hello World' ]
  [ "$(cat "$STATE/player")" = edge.i1 ]
}

@test "Edge rejects a fresh bridge with a different title and no recent match" {
  bridge 'Another song'
  listen_track edge.i1 A
  assert_blocked
}

@test "Edge rejects a stale bridge even with a matching title" {
  bridge A "$(( $(date +%s%3N) - 60000 ))"
  listen_track edge.i1 A
  assert_blocked
}

@test "native YouTube Music players need no bridge including instances" {
  for player in ytm_player ytm_player.i1 ytermusic ytermusic.i1; do
    listen_track "$player" A
    [ "$(jq -r .state <<<"${lines[1]}")" = playing ]
    [ "$(cat "$STATE/player")" = "$player" ]
  done
}

@test "Spotify is rejected even when playerctl emits it" {
  listen_track spotify A
  assert_blocked
}

@test "other browsers and lookalike player names are rejected" {
  bridge A
  for player in firefox chromium vlc ytm_player_fake edge_fake; do
    listen_track "$player" A
    assert_blocked
  done
}

@test "fresh title mismatches pass only during the last match skew window" {
  bridge A
  gate_player_ok edge.i1 A
  gate_player_ok edge.i1 B
  GATE_LAST_MATCH_MS=$(( $(date +%s%3N) - 6000 ))
  ! gate_player_ok edge.i1 B
  bridge B
  gate_player_ok edge.i1 B
}

@test "a missing or stale bridge cannot use the mismatch skew allowance" {
  bridge A
  gate_player_ok edge.i1 A
  bridge A "$(( $(date +%s%3N) - 60000 ))"
  ! gate_player_ok edge.i1 B
  rm "$STATE/ytm-browser.json"
  ! gate_player_ok edge.i1 B
}

@test "title matching preserves multiline records and rejects empty normalized titles" {
  bridge $'Hello\nWorld'
  gate_player_ok edge 'HELLO world!'
  GATE_LAST_MATCH_MS=0
  bridge '!!!'
  ! gate_player_ok edge '???'
}

@test "a listener keeps its recent bridge match across successive records" {
  bridge A
  listener "printf 'Playing\\x1fedge.i1\\x1fA\\x1fX\\x1f\\x1f0\\x1e\\n'
printf 'Playing\\x1fedge.i1\\x1fB\\x1fX\\x1f\\x1f0\\x1e\\n'"
  run bash -c 'source "$1"; stream | emit_dedup' _ "$BATS_TEST_TMPDIR/eww/scripts/media"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [ "$(jq -r .title <<<"${lines[2]}")" = B ]
  [ "$(cat "$BATS_TEST_TMPDIR/island.log")" = 'auto 4' ]
}
@test "the gate preserves a matching multiline record unchanged" {
  bridge 'Hello World'
  listen_track edge.i1 $'Hello\nWorld'
  [ "$(jq -r .title <<<"${lines[1]}")" = $'Hello\nWorld' ]
  [ "$(jq -r .artist <<<"${lines[1]}")" = X ]
}

