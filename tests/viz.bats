# tests/viz.bats
setup() {
  load helpers
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN" "$XDG_RUNTIME_DIR/eww-island"
  export PATH="$BIN:$PATH"
  if [[ ! -f "$SCRIPTS/viz" ]]; then
    printf 'Missing production visualizer: %s/viz\n' "$SCRIPTS" >&2
    return 1
  fi
  source "$SCRIPTS/viz"
}

teardown() {
  if [[ -n ${owned_child:-} ]]; then
    kill "$owned_child" 2>/dev/null || :
    wait "$owned_child" 2>/dev/null || :
  fi
}

@test "six raw CAVA levels become newline-delimited JSON including silence" {
  run viz_frames <<'EOF'
0;1;2;6;7;8;
8;7;6;2;1;0;
0;0;0;0;0;0;
EOF
  [ "$status" -eq 0 ]
  [ "$output" = $'[0,1,2,6,7,8]\n[8,7,6,2,1,0]\n[0,0,0,0,0,0]' ]
}

@test "malformed CAVA frames are dropped whole without poisoning the next frame" {
  run viz_frames <<'EOF'
0;1;2;3;4;
0;1;2;3;4;5;6;
0;1;2;3;4;9;
0;1;2;3;4;-1;
0;1;2;3;4;08;
0;1;2;3;4;x;
0;1;2;3;4;5
0;1;2;3;4;5;garbage

1;2;3;4;5;6;
EOF
  [ "$status" -eq 0 ]
  [ "$output" = '[1,2,3,4,5,6]' ]
}

@test "PID ancestry accepts the owner and a real owned child but rejects an ancestor" {
  local owner=$BASHPID
  sleep 30 &
  owned_child=$!
  run viz_descendant "$owner" "$owner"
  [ "$status" -eq 0 ]
  run viz_descendant "$owned_child" "$owner"
  [ "$status" -eq 0 ]
  run viz_descendant "$owner" "$owned_child"
  [ "$status" -eq 1 ]
}

@test "PID ancestry rejects invalid or missing processes" {
  local pid
  for pid in '' invalid 0 -1 999999999; do
    run viz_descendant "$pid" "$BASHPID"
    [ "$status" -eq 1 ]
    run viz_descendant "$BASHPID" "$pid"
    [ "$status" -eq 1 ]
  done
}

@test "stream selection prefers uncorked then numerically greatest serial among owned PIDs" {
  local owner=$BASHPID
  sleep 30 &
  owned_child=$!
  run viz_select "$owner" <<EOF
[
 {"index":1,"corked":false,"properties":{"application.process.id":"$owner","object.serial":"99"}},
 {"index":2,"corked":false,"properties":{"application.process.id":"$owned_child","object.serial":"100"}},
 {"index":3,"corked":true,"properties":{"application.process.id":"$owner","object.serial":"900"}},
 {"index":4,"corked":false,"properties":{"application.process.id":"$PPID","object.serial":"9999"}}
]
EOF
  [ "$status" -eq 0 ]
  [ "$output" = 100 ]
}

@test "corked owned streams remain eligible when none is uncorked" {
  run viz_select "$BASHPID" <<EOF
[
 {"index":1,"corked":true,"properties":{"application.process.id":"$BASHPID","object.serial":"9"}},
 {"index":2,"corked":true,"properties":{"application.process.id":"$BASHPID","object.serial":"10"}}
]
EOF
  [ "$status" -eq 0 ]
  [ "$output" = 10 ]
}

@test "unowned or malformed stream identities never become capture targets" {
  run viz_select "$BASHPID" <<EOF
[
 {"index":1,"corked":false,"properties":{"application.process.id":"$PPID","object.serial":"900"}},
 {"index":2,"corked":false,"properties":{"application.process.id":"$BASHPID","object.serial":"invalid"}},
 {"index":3,"corked":false,"properties":{"object.serial":"901"}}
]
EOF
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

stub_target_tools() {
  export VIZ_TEST_OWNER=$BASHPID
  export VIZ_TEST_TMP="$BATS_TEST_TMPDIR"
  cat > "$BIN/busctl" <<'EOF'
#!/usr/bin/env bash
[[ $* == "--user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetConnectionUnixProcessID s org.mpris.MediaPlayer2.edge.known" ]] || exit 1
printf 'u %s\n' "$VIZ_TEST_OWNER"
EOF
  cat > "$BIN/pactl" <<'EOF'
#!/usr/bin/env bash
if [[ $* == '-f json list sink-inputs' ]]; then
  printf '[{"index":5,"corked":false,"properties":{"application.process.id":"%s","object.serial":"321"}}]\n' "$VIZ_TEST_OWNER"
elif [[ $* == subscribe ]]; then
  exec sleep 30
else
  exit 1
fi
EOF
  chmod +x "$BIN/busctl" "$BIN/pactl"
}

@test "target resolution uses the active MPRIS instance DBus owner and owned stream serial" {
  stub_target_tools
  run viz_target edge.known
  [ "$status" -eq 0 ]
  [ "$output" = 321 ]
  run viz_target edge.unknown
  [ "$status" -eq 0 ]
  [ -z "$output" ]
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
