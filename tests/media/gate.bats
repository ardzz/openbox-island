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

@test "a silent Edge track expires and closes when bridge freshness runs out" {
  export ISLAND_BRIDGE_MAX_AGE_MS=200
  bridge A
  listener "printf 'Playing\\x1fedge.i1\\x1fA\\x1fX\\x1f\\x1f0\\x1e\\n'
sleep 0.6"
  run bash -c 'source "$1"; stream | emit_dedup' _ "$BATS_TEST_TMPDIR/eww/scripts/media"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [ "$(jq -r .state <<<"${lines[1]}")" = playing ]
  [ "${lines[2]}" = "$NONE_JSON" ]
  [ "$(cat "$STATE/player")" = "" ]
  [ "$(cat "$BATS_TEST_TMPDIR/island.log")" = close ]
}

@test "a silent skew-admitted track expires without another metadata record" {
  export ISLAND_BRIDGE_SKEW_MS=100
  bridge A
  listener "printf 'Playing\\x1fedge.i1\\x1fA\\x1fX\\x1f\\x1f0\\x1e\\n'
printf 'Playing\\x1fedge.i1\\x1fB\\x1fX\\x1f\\x1f0\\x1e\\n'
sleep 0.5"
  run bash -c 'source "$1"; stream | emit_dedup' _ "$BATS_TEST_TMPDIR/eww/scripts/media"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 4 ]
  [ "$(jq -r .title <<<"${lines[2]}")" = B ]
  [ "${lines[3]}" = "$NONE_JSON" ]
  [ "$(cat "$BATS_TEST_TMPDIR/island.log")" = $'auto 4\nclose' ]
}

@test "a rejected Edge no-track record bypasses loading grace" {
  export ISLAND_MEDIA_GRACE=2
  bridge A
  listener "printf 'Playing\\x1fedge.i1\\x1fA\\x1fX\\x1f\\x1f0\\x1e\\n'
sleep 0.1
rm \"$STATE/ytm-browser.json\"
printf 'Stopped\\x1fedge.i1\\x1f\\x1f\\x1f\\x1f0\\x1e\\n'
sleep 0.2"
  run bash -c 'source "$1"; stream | emit_dedup' _ "$BATS_TEST_TMPDIR/eww/scripts/media"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [ "${lines[2]}" = "$NONE_JSON" ]
  [ "$(cat "$STATE/player")" = "" ]
  [ "$(cat "$BATS_TEST_TMPDIR/island.log")" = close ]
}

@test "an empty Edge record with missing bridge closes immediately without loading" {
  export ISLAND_MEDIA_GRACE=2
  bridge A
  listener "printf 'Playing\\x1fedge.i1\\x1fA\\x1fX\\x1f\\x1f0\\x1e\\n'
sleep 0.1
rm \"$STATE/ytm-browser.json\"
printf '\\n'
sleep 0.2"
  run bash -c 'source "$1"; stream | emit_dedup' _ "$BATS_TEST_TMPDIR/eww/scripts/media"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [ "$(jq -r .state <<<"${lines[1]}")" = playing ]
  [ "${lines[2]}" = "$NONE_JSON" ]
  [ "$(cat "$STATE/player")" = "" ]
  [ "$(cat "$BATS_TEST_TMPDIR/island.log")" = close ]
}

@test "Japanese titles stay meaningful and Unicode case folding preserves exact matching" {
  bridge '夜に駆ける'
  listen_track edge.i1 '夜に駆ける'
  [ "$(jq -r .state <<<"${lines[1]}")" = playing ]
  GATE_LAST_MATCH_MS=0
  ! gate_player_ok edge.i1 '夜に駆けない'
  bridge 'ÉTÉ,　夜!'
  gate_player_ok edge.i1 'été 夜'
}

recover_bridge() {
  export ISLAND_BRIDGE_RECHECK_MS=20
  listener "printf 'Playing\\x1fedge.i1\\x1fA\\x1fX\\x1f\\x1f0\\x1e\\n'
while [[ ! -s \"$STATE/media.json\" ]]; do sleep 0.01; done
for ((i=0; i<100; i++)); do
  [[ -e \"$STATE/rejected\" ]] && break
  sleep 0.01
done
${1:-}
printf '%s\n' '{\"title\":\"A\",\"ts\":'\"\$(date +%s%3N)\"'}' > \"$STATE/ytm-browser.json.tmp\"
mv \"$STATE/ytm-browser.json.tmp\" \"$STATE/ytm-browser.json\"
for ((i=0; i<100; i++)); do
  [[ \$(jq -r .state \"$STATE/media.json\") == playing ]] && exit 0
  sleep 0.01
done"
  run bash -c 'source "$1"
    original=$(declare -f gate_record)
    eval "${original/gate_record ()/original_gate_record ()}"
    gate_record() {
      if original_gate_record "$1"; then return 0; fi
      touch "$ISLAND_STATE/rejected"
      return 1
    }
    stream | emit_dedup' _ "$BATS_TEST_TMPDIR/eww/scripts/media"
  [ "$status" -eq 0 ]
  if [[ -n ${1:-} ]]; then assert_blocked; return; fi
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "$NONE_JSON" ]
  [ "$(jq -r '.state + ":" + .title' <<<"${lines[1]}")" = playing:A ]
  [ "$(cat "$BATS_TEST_TMPDIR/island.log")" = 'auto 4' ]
}

@test "a rejected Edge candidate recovers when missing bridge arrives without metadata" {
  recover_bridge
}

@test "a rejected Edge candidate recovers when stale bridge becomes fresh without metadata" {
  bridge A "$(( $(date +%s%3N) - 60000 ))"
  recover_bridge
}

@test "an empty playerctl record drops a rejected Edge candidate" {
  recover_bridge "printf '\\n'"
}

@test "a new unsupported player record replaces a rejected Edge candidate" {
  recover_bridge "printf 'Playing\\x1fspotify\\x1fA\\x1fX\\x1f\\x1f0\\x1e\\n'"
}
