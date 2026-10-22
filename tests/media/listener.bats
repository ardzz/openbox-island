# tests/media/listener.bats: the media listener: output, island actions and the grace period
load common

@test "the listener emits one JSON per change, drives the island, and honors player priority" {
  export ISLAND_MEDIA_GRACE=0.3
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
  [ "${#lines[@]}" -eq 6 ]
  [ "$(jq -r .state <<<"${lines[0]}")" = none ]
  [ "$(jq -r .title <<<"${lines[1]}")" = A ]
  [ "$(jq -r .title <<<"${lines[2]}")" = B ]
  [ "$(jq -r .title <<<"${lines[3]}")" = $'C1\nC2' ]
  [ "$(jq -r .state <<<"${lines[4]}")" = loading ]
  [ "$(jq -r .state <<<"${lines[5]}")" = none ]
  [ "$(cat "$STATE/media.json")" = "${lines[5]}" ]
  [ "$(cat "$BATS_TEST_TMPDIR/island.log")" = $'auto 4\nauto 4\nclose' ]
  [[ "$(cat "$BATS_TEST_TMPDIR/playerctl.args")" == "--player=$(tr -d '[:space:]' < "$REPO/eww/players") --follow metadata --format "* ]]
}

@test "a brief gap between tracks shows loading on the same player, never closing the island" {
  export ISLAND_MEDIA_GRACE=1
  listener "printf 'Playing\x1fedge.i1\x1fA\x1fX\x1f\x1f1000000\x1e\n'
printf '\n'
printf 'Stopped\x1fedge.i1\x1f\x1f\x1f\x1f\x1e\n'
printf 'Playing\x1fedge.i1\x1f\x1f\x1f\x1f\x1e\n'
sleep 0.3
cat \"\$XDG_RUNTIME_DIR/eww-island/player\" > \"$BATS_TEST_TMPDIR/player.during\"
cat \"\$XDG_RUNTIME_DIR/eww-island/media.json\" > \"$BATS_TEST_TMPDIR/media.during\"
printf 'Playing\x1fedge.i1\x1fB\x1fY\x1f\x1f2000000\x1e\n'
sleep 5"
  run timeout 1.5 "$BATS_TEST_TMPDIR/eww/scripts/media"
  [ "$status" -eq 124 ]
  [ "${#lines[@]}" -eq 4 ]
  [ "$(jq -r .title <<<"${lines[1]}")" = A ]
  [ "${lines[2]}" = "$(loading_json edge.i1)" ]
  [ "$(jq -c '[.state,.title,.artist]' <<<"${lines[3]}")" = '["playing","B","Y"]' ]
  [ "$(cat "$BATS_TEST_TMPDIR/media.during")" = "${lines[2]}" ]
  [ "$(cat "$BATS_TEST_TMPDIR/player.during")" = edge.i1 ]
  [ "$(cat "$STATE/media.json")" = "${lines[3]}" ]
  [ "$(cat "$BATS_TEST_TMPDIR/island.log")" = 'auto 4' ]
}

@test "no player for the whole grace period ends the music and closes the island" {
  export ISLAND_MEDIA_GRACE=0.3
  listener "printf 'Playing\x1fedge.i1\x1fA\x1fX\x1f\x1f1000000\x1e\n'
printf '\n'
sleep 5"
  run timeout 1.2 "$BATS_TEST_TMPDIR/eww/scripts/media"
  [ "$status" -eq 124 ]
  [ "${#lines[@]}" -eq 4 ]
  [ "$(jq -r .state <<<"${lines[2]}")" = loading ]
  [ "$(jq -r .state <<<"${lines[3]}")" = none ]
  [ "$(cat "$STATE/media.json")" = "${lines[3]}" ]
  [ "$(cat "$STATE/player")" = "" ]
  [ "$(cat "$BATS_TEST_TMPDIR/island.log")" = close ]
}

@test "a player that stays stopped still closes the island after the grace period" {
  export ISLAND_MEDIA_GRACE=0.3
  listener "printf 'Paused\x1fedge.i1\x1fA\x1fX\x1f\x1f1000000\x1e\n'
sleep 0.1
printf 'Stopped\x1fedge.i1\x1fA\x1fX\x1f\x1f1000000\x1e\n'
sleep 5"
  run timeout 1.2 "$BATS_TEST_TMPDIR/eww/scripts/media"
  [ "$status" -eq 124 ]
  [ "$(jq -r .state <<<"${lines[-1]}")" = none ]
  [ "$(jq -r .state <<<"${lines[-2]}")" = loading ]
  [ "$(cat "$BATS_TEST_TMPDIR/island.log")" = close ]
}

@test "an untitled track that outlasts the grace period is shown as it is" {
  export ISLAND_MEDIA_GRACE=0.3
  listener "printf 'Playing\x1fedge.i1\x1fA\x1fX\x1f\x1f1000000\x1e\n'
printf 'Playing\x1fedge.i1\x1f\x1f\x1f\x1f5000000\x1e\n'
sleep 5"
  run timeout 1.2 "$BATS_TEST_TMPDIR/eww/scripts/media"
  [ "$status" -eq 124 ]
  [ "$(jq -r .state <<<"${lines[2]}")" = loading ]
  [ "$(jq -c '[.state,.title,.length]' <<<"${lines[3]}")" = '["playing","",5]' ]
  [ "$(cat "$BATS_TEST_TMPDIR/island.log")" = 'auto 4' ]
}

@test "a gap before the first track shows no loading state" {
  export ISLAND_MEDIA_GRACE=1
  listener "printf '\n'
printf 'Playing\x1fedge.i1\x1fA\x1fX\x1f\x1f1000000\x1e\n'
sleep 5"
  run timeout 0.8 "$BATS_TEST_TMPDIR/eww/scripts/media"
  [ "${#lines[@]}" -eq 2 ]
  [ "$(jq -r .title <<<"${lines[1]}")" = A ]
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

@test "listener finishes close before dispatching the following auto (grace 0 closes at once)" {
  export ISLAND_MEDIA_GRACE=0
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
