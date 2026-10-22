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

@test "six raw CAVA levels 0-12 become newline-delimited JSON including silence" {
  run viz_frames <<'EOF'
0;1;2;6;7;8;
9;10;11;12;12;0;
12;11;10;9;8;7;
0;0;0;0;0;0;
EOF
  [ "$status" -eq 0 ]
  [ "$output" = $'[0,1,2,6,7,8]\n[9,10,11,12,12,0]\n[12,11,10,9,8,7]\n[0,0,0,0,0,0]' ]
}

@test "malformed CAVA frames are dropped whole without poisoning the next frame" {
  run viz_frames <<'EOF'
0;1;2;3;4;
0;1;2;3;4;5;6;
0;1;2;3;4;13;
0;1;2;3;4;99;
0;1;2;3;4;120;
0;1;2;3;4;-1;
0;1;2;3;4;08;
0;1;2;3;4;012;
0;1;2;3;4;x;
0;1;2;3;4;5
0;1;2;3;4;5;garbage

1;2;3;4;5;6;
EOF
  [ "$status" -eq 0 ]
  [ "$output" = '[1,2,3,4,5,6]' ]
}

@test "unchanged frames are emitted once until the levels change" {
  run bash -c 'source "$1"; last=""
    for f in "[1,2,3,4,5,6]" "[1,2,3,4,5,6]" "[12,0,0,0,0,0]" "[12,0,0,0,0,0]" "[1,2,3,4,5,6]"; do
      viz_emit "$f"
    done' _ "$SCRIPTS/viz"
  [ "$status" -eq 0 ]
  [ "$output" = $'[1,2,3,4,5,6]\n[12,0,0,0,0,0]\n[1,2,3,4,5,6]' ]
}

# The fake reports $VIZ_TEST_TMP/xrandr.out, or fails like an unreachable display.
stub_xrandr() {
  export VIZ_TEST_TMP="$BATS_TEST_TMPDIR" DISPLAY=:0
  unset ISLAND_VIZ_FPS
  cat > "$BIN/xrandr" <<'EOF'
#!/usr/bin/env bash
[[ $* == --current ]] || exit 2
cat "$VIZ_TEST_TMP/xrandr.out"
EOF
  chmod +x "$BIN/xrandr"
  if (( $# )); then printf '%s\n' "$@" > "$BATS_TEST_TMPDIR/xrandr.out"; fi
}

laptop_144=(
  'Screen 0: minimum 8 x 8, current 1920 x 1080, maximum 32767 x 32767'
  'eDP-1-1 connected 1920x1080+0+0 (normal left inverted right x axis y axis) 344mm x 194mm'
  '   1920x1080    144.00*+  60.00 +  59.97    59.96    59.93  '
  '   1680x1050     59.95    59.88  '
  'HDMI-1-1 disconnected (normal left inverted right x axis y axis)'
)

@test "visualizer fps follows the current mode of the origin monitor" {
  stub_xrandr "${laptop_144[@]}"
  run viz_fps
  [ "$status" -eq 0 ]
  [ "$output" = 144 ]
  stub_xrandr 'Screen 0: minimum 8 x 8, current 1920 x 1080, maximum 32767 x 32767' \
    'eDP-1 connected primary 1920x1080+0+0 (normal left inverted right x axis y axis) 344mm x 194mm' \
    '   1920x1080     60.00*+  48.00  '
  run viz_fps
  [ "$output" = 60 ]
}

@test "fractional refresh rates round to the nearest integer fps" {
  stub_xrandr 'Screen 0: minimum 8 x 8, current 1920 x 1080, maximum 32767 x 32767' \
    'DP-2 connected 1920x1080+0+0 (normal left inverted right x axis y axis) 527mm x 296mm' \
    '   1920x1080     60.00 +  59.94*   50.00  '
  run viz_fps
  [ "$output" = 60 ]
  stub_xrandr 'DP-2 connected 1920x1080+0+0 (normal) 527mm x 296mm' '   1920x1080    143.50*'
  run viz_fps
  [ "$output" = 144 ]
}

@test "an external monitor listed first does not override the origin monitor" {
  stub_xrandr 'Screen 0: minimum 8 x 8, current 4480 x 1440, maximum 32767 x 32767' \
    'HDMI-1 connected 2560x1440+1920+0 (normal left inverted right x axis y axis) 597mm x 336mm' \
    '   2560x1440     59.95 +  74.97*  ' \
    '   1920x1080     60.00    50.00  ' \
    'eDP-1 connected primary 1920x1080+0+0 (normal left inverted right x axis y axis) 344mm x 194mm' \
    '   1920x1080    144.00 +  120.00*  '
  run viz_fps
  [ "$output" = 120 ]
}

@test "the primary monitor is used when no output sits at the screen origin" {
  stub_xrandr 'Screen 0: minimum 8 x 8, current 4480 x 2520, maximum 32767 x 32767' \
    'HDMI-1 connected 2560x1440+1920+0 (normal) 597mm x 336mm' \
    '   2560x1440     74.97*  ' \
    'eDP-1 connected primary 1920x1080+0+1440 (normal) 344mm x 194mm' \
    '   1920x1080    165.00*+  '
  run viz_fps
  [ "$output" = 165 ]
}

@test "refresh rates beyond 240 Hz clamp to 240 fps" {
  stub_xrandr 'DP-1 connected 1920x1080+0+0 (normal) 527mm x 296mm' '   1920x1080    360.00*+'
  run viz_fps
  [ "$output" = 240 ]
}

@test "ISLAND_VIZ_FPS overrides the monitor when it is an integer from 1 to 240" {
  local fps
  stub_xrandr "${laptop_144[@]}"
  for fps in 1 75 240; do
    ISLAND_VIZ_FPS=$fps run viz_fps
    [ "$output" = "$fps" ]
  done
}

@test "invalid ISLAND_VIZ_FPS is ignored in favour of the monitor rate" {
  local fps
  stub_xrandr "${laptop_144[@]}"
  for fps in '' 0 241 -5 60.5 abc 0x3c 060; do
    ISLAND_VIZ_FPS=$fps run viz_fps
    [ "$output" = 144 ]
  done
}

@test "fps falls back to 60 without a usable display or xrandr" {
  stub_xrandr "${laptop_144[@]}"
  run bash -c 'unset DISPLAY; source "$1"; viz_fps' _ "$SCRIPTS/viz"
  [ "$output" = 60 ]
  stub_xrandr 'Screen 0: garbage' 'eDP-1 connected 1920x1080+0+0' '   1920x1080    fast*'
  run viz_fps
  [ "$output" = 60 ]
  rm "$BATS_TEST_TMPDIR/xrandr.out"
  run viz_fps
  [ "$output" = 60 ]
  rm "$BIN/xrandr"
  run bash -c 'source "$1"; PATH=$2; viz_fps' _ "$SCRIPTS/viz" "$BIN"
  [ "$output" = 60 ]
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
