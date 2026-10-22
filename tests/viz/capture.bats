# tests/viz/capture.bats: capture lifecycle: emitting, starting and stopping the audio workers
load common

@test "unchanged frames are emitted once until the levels change" {
  run bash -c 'source "$1"; last=""
    for f in "[1,2,3,4,5,6]" "[1,2,3,4,5,6]" "[12,0,0,0,0,0]" "[12,0,0,0,0,0]" "[1,2,3,4,5,6]"; do
      viz_emit "$f"
    done' _ "$SCRIPTS/viz"
  [ "$status" -eq 0 ]
  [ "$output" = $'[1,2,3,4,5,6]\n[12,0,0,0,0,0]\n[1,2,3,4,5,6]' ]
}

@test "unknown active owner starts flat and never starts audio capture" {
  stub_target_tools
  printf 'edge.unknown\n' > "$XDG_RUNTIME_DIR/eww-island/player"
  cat > "$BIN/pw-record" <<'EOF'
#!/usr/bin/env bash
printf 'capture\n' >> "$VIZ_TEST_TMP/capture.log"
exit 1
EOF
  cat > "$BIN/cava" <<'EOF'
#!/usr/bin/env bash
printf 'cava\n' >> "$VIZ_TEST_TMP/capture.log"
exit 1
EOF
  cat > "$BIN/inotifywait" <<'EOF'
#!/usr/bin/env bash
exec sleep 30
EOF
  chmod +x "$BIN/pw-record" "$BIN/cava" "$BIN/inotifywait"
  run timeout 0.5 bash -c 'exec "$1" 2>"$2"' _ "$SCRIPTS/viz" "$BATS_TEST_TMPDIR/viz.stderr"
  [ "$status" -eq 124 ]
  [ "$output" = '[0,0,0,0,0,0]' ]
  [ ! -e "$BATS_TEST_TMPDIR/capture.log" ]
}

# Runs viz against the owned edge.known stream and checks the config CAVA was handed.
expect_rendered_cava() {
  local fps=$1 noise=$2 template="$REPO/eww/cava.conf" rendered="$BATS_TEST_TMPDIR/cava.rendered"
  rm -f "$rendered" "$BATS_TEST_TMPDIR/cava.path"
  run timeout 1 bash -c 'exec "$1" 2>"$2"' _ "$SCRIPTS/viz" "$BATS_TEST_TMPDIR/viz.stderr"
  [ "$status" -eq 124 ]
  [ -f "$rendered" ]
  [[ $(< "$BATS_TEST_TMPDIR/cava.path") == "$XDG_RUNTIME_DIR/eww-island/"* ]]
  [ ! -e "$(< "$BATS_TEST_TMPDIR/cava.path")" ]
  [ "$(grep -c '^framerate = ' "$rendered")" -eq 1 ]
  [ "$(grep -c '^noise_reduction = ' "$rendered")" -eq 1 ]
  grep -qx "framerate = $fps" "$rendered"
  grep -qx "noise_reduction = $noise" "$rendered"
  diff <(grep -Ev '^(framerate|noise_reduction) = ' "$rendered") \
    <(grep -Ev '^(framerate|noise_reduction) = ' "$template")
}

@test "capture renders a runtime CAVA config for the current fps and removes it on exit" {
  stub_target_tools
  stub_xrandr "${laptop_144[@]}"
  printf 'edge.known\n' > "$XDG_RUNTIME_DIR/eww-island/player"
  cat > "$BIN/pw-record" <<'EOF'
#!/usr/bin/env bash
exec sleep 30
EOF
  cat > "$BIN/cava" <<'EOF'
#!/usr/bin/env bash
[[ $1 == -p && $# -eq 2 ]] || exit 2
cp "$2" "$VIZ_TEST_TMP/cava.rendered"
printf '%s\n' "$2" > "$VIZ_TEST_TMP/cava.path"
exec sleep 30
EOF
  cat > "$BIN/inotifywait" <<'EOF'
#!/usr/bin/env bash
exec sleep 30
EOF
  chmod +x "$BIN/pw-record" "$BIN/cava" "$BIN/inotifywait"
  # Settle time of the integral filter stays that of noise_reduction 90 at 60 fps.
  expect_rendered_cava 144 88
  ISLAND_VIZ_FPS=60 expect_rendered_cava 60 90
  ISLAND_VIZ_FPS=20 expect_rendered_cava 20 76
  ISLAND_VIZ_FPS=240 expect_rendered_cava 240 86
  # Below ~7 fps frames are already further apart than the settle time: no smoothing.
  ISLAND_VIZ_FPS=5 expect_rendered_cava 5 0
}

@test "stubborn owned capture workers are killed and reaped before levels clear" {
  run_shutdown_regression capture
}

@test "cleanup bounds stubborn capture and watcher shutdown without killing unrelated children" {
  run_shutdown_regression cleanup
}

run_shutdown_regression() {
  cat > "$BATS_TEST_TMPDIR/shutdown" <<'EOF'
#!/usr/bin/env bash
source "$1"
mode=$2
work=$3
mkdir -p "$work"
mkfifo "$work/frames" "$work/events" "$work/ready"
exec {frames}<>"$work/frames" {events}<>"$work/events" {ready}<>"$work/ready"
workers=()
watchdog=''
cleanup_test() {
  local pid
  for pid in "${workers[@]}" "$watchdog" "${unrelated:-}"; do
    [[ -z $pid ]] || kill -KILL "$pid" 2>/dev/null || :
  done
  for pid in "${workers[@]}" "$watchdog" "${unrelated:-}"; do
    [[ -z $pid ]] || wait "$pid" 2>/dev/null || :
  done
}
trap cleanup_test EXIT
trap 'exit 1' TERM INT
count=2
[[ $mode != cleanup ]] || count=4
for ((i=0; i<count; i++)); do
  bash -c 'trap "" TERM; printf "ready\n"; exec sleep 30' > "$work/ready" &
  workers+=("$!")
  IFS= read -r -t 1 -u "$ready" ack || exit 1
  [[ $ack == ready ]] || exit 1
done
sleep 30 &
unrelated=$!
recorder=${workers[0]}
analyzer=${workers[1]}
pulse_watch=${workers[2]:-}
state_watch=${workers[3]:-}
current=321
last='[8,8,8,8,8,8]'
# The watchdog releases even the old unbounded wait, then the duration assertion
# fails. Only the actual owner reaps workers; no orphaned stubborn sleep remains.
(
  IFS= read -r -t 2 -u "$ready" ignored || :
  kill -KILL "${workers[@]}" 2>/dev/null || :
) &
watchdog=$!
start=${EPOCHREALTIME/./}
if [[ $mode == cleanup ]]; then
  viz_cleanup
else
  viz_stop_capture
fi
elapsed=$(( ${EPOCHREALTIME/./} - start ))
trap cleanup_test EXIT
[[ -z $recorder && -z $analyzer && -z $current ]] || exit 1
[[ $last == '[0,0,0,0,0,0]' ]] || exit 1
limit=900000
[[ $mode != cleanup ]] || limit=1400000
(( elapsed < limit )) || exit 1
for pid in "${workers[@]}"; do
  [[ ! -e /proc/$pid ]] || exit 1
done
kill -0 "$unrelated" || exit 1
EOF
  run timeout -k 1 4 bash "$BATS_TEST_TMPDIR/shutdown" "$SCRIPTS/viz" "$1" "$BATS_TEST_TMPDIR/shutdown-work"
  [ "$status" -eq 0 ]
  [ "$output" = '[0,0,0,0,0,0]' ]
}
