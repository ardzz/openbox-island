# tests/media.bats
setup() {
  load helpers
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache" XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  PATH="$BIN:$PATH"
  source "$SCRIPTS/media"
}
# line FIELD...: one playerctl --format line (fields joined by \x1f).
line() { local IFS=$'\x1f'; printf '%s' "$*"; }

@test "a playing track becomes island JSON with whole seconds and a decoded cover path" {
  touch "$BATS_TEST_TMPDIR/a b.png"
  run media_json "$(line Playing edge.instance11487 'Heroes Tonight' 'Janji, Johnning' "file://$BATS_TEST_TMPDIR/a%20b.png" 290366666)"
  [ "$status" -eq 0 ]
  [ "$(jq -r .art <<<"$output")" = "$BATS_TEST_TMPDIR/a b.png" ]
  [ "$(jq -c 'del(.art)' <<<"$output")" = '{"state":"playing","player":"edge.instance11487","title":"Heroes Tonight","artist":"Janji, Johnning","length":290,"length_text":"4:50"}' ]
}

@test "a cover path that would break CSS is served through a safe cache link" {
  touch "$BATS_TEST_TMPDIR/album's cover.jpg"
  run resolve_art "file://$BATS_TEST_TMPDIR/album%27s%20cover.jpg"
  [ "$status" -eq 0 ]
  [[ $output == "$ART_CACHE/"* ]]
  [[ $output != *"'"* ]]
  [ "$(readlink "$output")" = "$BATS_TEST_TMPDIR/album's cover.jpg" ]
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

@test "an http cover is served from cache without downloading again" {
  url='https://lh3.googleusercontent.com/abc=w120'
  file="$ART_CACHE/$(printf '%s' "$url" | sha1sum | cut -c1-40)"
  mkdir -p "$ART_CACHE"; printf 'img' > "$file"
  printf '#!/usr/bin/env bash\necho "$*" >> "%s/curl.log"\nexit 22\n' "$BATS_TEST_TMPDIR" > "$BIN/curl"; chmod +x "$BIN/curl"
  run resolve_art "$url"
  [ "$output" = "$file" ]
  [ ! -e "$BATS_TEST_TMPDIR/curl.log" ]
}

@test "an http cover is downloaded once into the cache" {
  cat > "$BIN/curl" <<'EOF'
#!/usr/bin/env bash
while (( $# )); do if [[ $1 == -o ]]; then printf 'img' > "$2"; fi; shift; done
EOF
  chmod +x "$BIN/curl"
  run resolve_art 'https://example.invalid/cover.jpg'
  [ "$status" -eq 0 ]
  [[ $output == "$ART_CACHE/"* ]]
  [ "$(cat "$output")" = img ]
}

@test "a failed download leaves no cover and no partial file" {
  cat > "$BIN/curl" <<'EOF'
#!/usr/bin/env bash
while (( $# )); do if [[ $1 == -o ]]; then printf 'half' > "$2"; fi; shift; done
exit 28
EOF
  chmod +x "$BIN/curl"
  run resolve_art 'https://example.invalid/x.jpg'
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
  [ -z "$(find "$ART_CACHE" -type f 2>/dev/null)" ]
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

@test "the listener emits one JSON per change, drives the island, and honors player priority" {
  mkdir -p "$BATS_TEST_TMPDIR/eww"
  cp -r "$SCRIPTS" "$BATS_TEST_TMPDIR/eww/scripts"
  cp "$REPO/eww/players" "$BATS_TEST_TMPDIR/eww/players"
  printf '#!/usr/bin/env bash\necho "$*" >> "%s/island.log"\necho polluted\n' "$BATS_TEST_TMPDIR" \
    > "$BATS_TEST_TMPDIR/eww/scripts/island"
  chmod +x "$BATS_TEST_TMPDIR/eww/scripts/island"
  cat > "$BIN/playerctl" <<EOF
#!/usr/bin/env bash
echo "\$*" > "$BATS_TEST_TMPDIR/playerctl.args"
printf 'Playing\x1fedge.i1\x1fA\x1fX\x1f\x1f1000000\x1e\n'
printf 'Playing\x1fedge.i1\x1fA\x1fX\x1f\x1f1000000\x1e\n'
sleep 0.2
printf 'Playing\x1fedge.i1\x1fB\x1fX\x1f\x1f1000000\x1e\n'
sleep 0.2
printf 'Playing\x1fedge.i1\x1fC1\nC2\x1fX\x1f\x1f1000000\x1e\n'
printf '\n'
sleep 5
EOF
  chmod +x "$BIN/playerctl"
  run timeout 1.5 "$BATS_TEST_TMPDIR/eww/scripts/media"
  [ "$status" -eq 124 ]
  [ "${#lines[@]}" -eq 5 ]
  [ "$(jq -r .state <<<"${lines[0]}")" = none ]
  [ "$(jq -r .title <<<"${lines[1]}")" = A ]
  [ "$(jq -r .title <<<"${lines[2]}")" = B ]
  [ "$(jq -r .title <<<"${lines[3]}")" = $'C1\nC2' ]
  [ "$(jq -r .state <<<"${lines[4]}")" = none ]
  [ "$(cat "$STATE/media.json")" = "${lines[4]}" ]
  [ "$(cat "$BATS_TEST_TMPDIR/island.log")" = $'auto 4\nauto 4\nclose' ]
  [[ "$(cat "$BATS_TEST_TMPDIR/playerctl.args")" == "--player=ytermusic,edge,%any --follow metadata --format "* ]]
}

@test "a silent player source still reports no player and clears a stale player" {
  mkdir -p "$BATS_TEST_TMPDIR/eww" "$XDG_RUNTIME_DIR/eww-island"
  cp -r "$SCRIPTS" "$BATS_TEST_TMPDIR/eww/scripts"
  cp "$REPO/eww/players" "$BATS_TEST_TMPDIR/eww/players"
  printf '#!/usr/bin/env bash\necho "$*" >> "%s/island.log"\necho polluted\n' "$BATS_TEST_TMPDIR" \
    > "$BATS_TEST_TMPDIR/eww/scripts/island"
  chmod +x "$BATS_TEST_TMPDIR/eww/scripts/island"
  printf '#!/usr/bin/env bash\nsleep 5\n' > "$BIN/playerctl"
  chmod +x "$BIN/playerctl"
  echo edge.old > "$XDG_RUNTIME_DIR/eww-island/player"
  run timeout 1 "$BATS_TEST_TMPDIR/eww/scripts/media"
  [ "$status" -eq 124 ]
  [ "$output" = '{"state":"none","player":"","title":"","artist":"","art":"","length":0,"length_text":"0:00"}' ]
  [ "$(cat "$XDG_RUNTIME_DIR/eww-island/player")" = "" ]
  [ "$(cat "$STATE/media.json")" = "$output" ]
}

@test "a paused track change restarts the marquee but resuming the same track does not" {
  export FAKE_DATE_COUNTER="$BATS_TEST_TMPDIR/date-counter" FAKE_ACK="$BATS_TEST_TMPDIR/ack"
  echo 10000 > "$FAKE_DATE_COUNTER"
  mkfifo "$FAKE_ACK"
  cat > "$BIN/date" <<'EOF'
#!/usr/bin/env bash
read -r now < "$FAKE_DATE_COUNTER"
echo $(( now + 1 )) | tee "$FAKE_DATE_COUNTER"
EOF
  cat > "$BIN/playerctl" <<'EOF'
#!/usr/bin/env bash
printf 'Playing\x1fedge.i1\x1fA\x1fX\x1f\x1f1000000\x1e\n'
read -r _ < "$FAKE_ACK"
printf 'Paused\x1fedge.i1\x1fB\x1fX\x1f\x1f1000000\x1e\n'
read -r _ < "$FAKE_ACK"
printf 'Playing\x1fedge.i1\x1fB\x1fX\x1f\x1f1000000\x1e\n'
read -r _ < "$FAKE_ACK"
EOF
  chmod +x "$BIN/date" "$BIN/playerctl"
  mkdir -p "$STATE"; echo 123 > "$STATE/marquee_at"
  snapshots() {
    stream | while IFS= read -r json; do
      [[ $(jq -r .state <<<"$json") != none ]] || continue
      printf '%s:%s\n' "$(jq -r '[.title,.state]|join(":")' <<<"$json")" "$(cat "$STATE/marquee_at")"
      echo next > "$FAKE_ACK"
    done
  }
  run snapshots
  [ "$status" -eq 0 ]
  [ "$output" = $'A:playing:10001\nB:paused:10002\nB:playing:10002' ]
}

@test "missing local artwork returns no cover and creates no alias" {
  run resolve_art "file://$BATS_TEST_TMPDIR/missing%27s.jpg"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
  [ ! -d "$ART_CACHE" ]
}

@test "listener finishes close before dispatching the following auto" {
  mkdir -p "$BATS_TEST_TMPDIR/eww"
  cp -r "$SCRIPTS" "$BATS_TEST_TMPDIR/eww/scripts"
  cp "$REPO/eww/players" "$BATS_TEST_TMPDIR/eww/players"
  export ACTION_LOG="$BATS_TEST_TMPDIR/actions"
  cat > "$BATS_TEST_TMPDIR/eww/scripts/island" <<'EOF'
#!/usr/bin/env bash
echo "$1 start" >> "$ACTION_LOG"
[[ $1 != close ]] || sleep 0.3
echo "$1 end" >> "$ACTION_LOG"
EOF
  cat > "$BIN/playerctl" <<'EOF'
#!/usr/bin/env bash
printf 'Playing\x1fedge.i1\x1fA\x1fX\x1f\x1f0\x1e\n'
printf '\n'
printf 'Playing\x1fedge.i1\x1fB\x1fX\x1f\x1f0\x1e\n'
EOF
  chmod +x "$BIN/playerctl" "$BATS_TEST_TMPDIR/eww/scripts/island"
  run bash -c 'source "$1"; stream' _ "$BATS_TEST_TMPDIR/eww/scripts/media"
  [ "$status" -eq 0 ]
  [ "$(cat "$ACTION_LOG")" = $'close start\nclose end\nauto start\nauto end' ]
}
