# tests/fullscreen.bats
# The watcher runs against fake X tools: windows live in $X (NAME, _NET_WM_STATE, geometry),
# the active window in $X/active. Spies print the current value, then relay their FIFO.
setup() {
  load helpers
  BIN="$BATS_TEST_TMPDIR/bin"; X="$BATS_TEST_TMPDIR/x"; mkdir -p "$BIN" "$X"
  export X XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run" EXPECTED_CFG="$REPO/eww"
  export FAKE_EWW_LOG="$BATS_TEST_TMPDIR/eww.log" FAKE_EWW_ACTIVE="$BATS_TEST_TMPDIR/active"
  unset ISLAND_FULLSCREEN_HIDE
  ST="$XDG_RUNTIME_DIR/eww-island"
  : > "$FAKE_EWW_LOG"; : > "$X/spies.log"; printf 'island: island\n' > "$FAKE_EWW_ACTIVE"
  cat > "$BIN/eww" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == --config && $2 == "$EXPECTED_CFG" ]]; then shift 2; else echo "bad config: $*" >> "$FAKE_EWW_LOG"; exit 1; fi
case $1 in
  ping|get) exit 0 ;;
  active-windows) cat "$FAKE_EWW_ACTIVE"; exit 0 ;;
  open) printf '%s: %s\n' "$2" "$2" >> "$FAKE_EWW_ACTIVE" ;;
  close) grep -vx "$2: $2" "$FAKE_EWW_ACTIVE" > "$FAKE_EWW_ACTIVE.tmp"; mv "$FAKE_EWW_ACTIVE.tmp" "$FAKE_EWW_ACTIVE" ;;
esac
printf '%s\n' "$*" >> "$FAKE_EWW_LOG"
EOF
  cat > "$BIN/xprop" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "-spy -root _NET_ACTIVE_WINDOW")
    echo root >> "$X/spies.log"
    printf '_NET_ACTIVE_WINDOW(WINDOW): window id # %s\n' "$(cat "$X/active")"
    exec cat "$X/root.fifo" ;;
  "-spy -id "*" _NET_WM_STATE")
    echo "$3" >> "$X/spies.log"
    printf '_NET_WM_STATE(ATOM) = %s\n' "$(cat "$X/$3.state")"
    exec cat "$X/$3.fifo" ;;
  "-id "*)
    [[ -e $X/$2.name ]] || { echo "xprop: error: Invalid window id format: $2." >&2; exit 1; }
    printf 'WM_NAME(STRING) = "%s"\n_NET_WM_STATE(ATOM) = %s\n' "$(cat "$X/$2.name")" "$(cat "$X/$2.state")" ;;
  *) echo "unexpected xprop $*" >> "$FAKE_EWW_LOG"; exit 1 ;;
esac
EOF
  cat > "$BIN/xdotool" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == getwindowgeometry && $2 == --shell && -e $X/$3.geom ]]; then
  read -r x y w h < "$X/$3.geom"
  printf 'WINDOW=%d\nX=%s\nY=%s\nWIDTH=%s\nHEIGHT=%s\nSCREEN=0\n' "$3" "$x" "$y" "$w" "$h"
else
  echo "unexpected xdotool $*" >> "$FAKE_EWW_LOG"; exit 1
fi
EOF
  # Monitor 0 (the island's) is 1920x1080 at the origin; monitor 1 sits to its right.
  cat > "$BIN/xrandr" <<'EOF'
#!/usr/bin/env bash
printf 'Monitors: 2\n 0: +*eDP-1 1920/344x1080/193+0+0  eDP-1\n 1: +HDMI-1 2560/597x1440/336+1920+0  HDMI-1\n'
EOF
  chmod +x "$BIN"/*
  PATH="$BIN:$PATH"
  mkfifo "$X/root.fifo"; exec {root_fd}<> "$X/root.fifo"
  echo 0x0 > "$X/active"
  sleep 1000 3>&- & DAEMON=$!
  WATCHER=''
}

teardown() {
  [[ -z $WATCHER ]] || kill "$WATCHER" 2>/dev/null || :
  kill "$DAEMON" 2>/dev/null || :
  pkill -f "$X/" 2>/dev/null || :
}

FS=_NET_WM_STATE_FULLSCREEN
# window ID NAME STATE "X Y W H": define a window.
window() {
  echo "$2" > "$X/$1.name"; echo "$3" > "$X/$1.state"; echo "$4" > "$X/$1.geom"
  mkfifo "$X/$1.fifo"; exec {fd}<> "$X/$1.fifo"
}
video() { window "$1" Video "$FS" '0 0 1920 1080'; }
editor() { window "$1" Editor _NET_WM_STATE_MAXIMIZED_VERT '0 0 1920 1080'; }
# activate ID: make ID the active window, as the window manager announces it.
activate() {
  echo "$1" > "$X/active"
  printf '_NET_ACTIVE_WINDOW(WINDOW): window id # %s\n' "$1" > "$X/root.fifo"
}
# set_state ID STATE: change ID's _NET_WM_STATE, as the window manager announces it.
set_state() {
  echo "$2" > "$X/$1.state"
  printf '_NET_WM_STATE(ATOM) = %s\n' "$2" > "$X/$1.fifo"
}
start_watcher() { "$SCRIPTS/fullscreen" "$DAEMON" 3>&- & WATCHER=$!; }
# until CMD...: retry CMD for up to 3 seconds.
until_true() {
  for _ in {1..150}; do "$@" && return 0; sleep 0.02; done
  "$@"
}
spied() { grep -qx "$1" "$X/spies.log"; }
hidden() { [[ -e $ST/fullscreen ]] && ! grep -q island "$FAKE_EWW_ACTIVE"; }
shown() { [[ ! -e $ST/fullscreen ]] && grep -qx 'island: island' "$FAKE_EWW_ACTIVE"; }
calls() { cat "$FAKE_EWW_LOG"; }
settle() { sleep 0.3; }

@test "a window going fullscreen hides both island windows; leaving brings the compact island back" {
  printf 'island: island\nisland-expanded: island-expanded\n' > "$FAKE_EWW_ACTIVE"
  editor 0x100; echo 0x100 > "$X/active"
  start_watcher
  until_true spied 0x100; settle
  [ "$(calls)" = "" ]
  set_state 0x100 "$FS"
  until_true hidden
  grep -qx 'close island-expanded' "$FAKE_EWW_LOG"
  grep -qx 'close island' "$FAKE_EWW_LOG"
  grep -qx 'close island-upcoming' "$FAKE_EWW_LOG"
  ! grep -q '^open' "$FAKE_EWW_LOG"
  : > "$FAKE_EWW_LOG"
  set_state 0x100 _NET_WM_STATE_MAXIMIZED_VERT
  until_true shown
  [ "$(calls)" = $'open island\nopen island-upcoming' ]
}

@test "switching the active window between fullscreen and normal windows hides and shows the island" {
  video 0x100; editor 0x200; echo 0x100 > "$X/active"
  start_watcher
  until_true hidden
  activate 0x200
  until_true shown
  # Only the active window is watched.
  until_true eval '! pgrep -f "$X/0x100.fifo" >/dev/null'
  activate 0x100
  until_true hidden
  [ "$(grep -c '^open island$' "$FAKE_EWW_LOG")" = 1 ]
}

@test "a fullscreen window on another monitor leaves the island alone" {
  window 0x300 Video "$FS" '1920 0 2560 1440'; echo 0x300 > "$X/active"
  start_watcher
  until_true spied 0x300; settle
  [ "$(calls)" = "" ]
  [ ! -e "$ST/fullscreen" ]
}

@test "the island's own windows never change the hidden state" {
  video 0x100; window 0x900 'Eww - island' '' '706 0 508 44'; echo 0x100 > "$X/active"
  start_watcher
  until_true hidden
  : > "$FAKE_EWW_LOG"
  activate 0x900; settle
  hidden
  [ "$(calls)" = "" ]
}

@test "the watcher exits with the eww daemon and leaves no spy behind" {
  video 0x100; echo 0x100 > "$X/active"
  start_watcher
  until_true spied 0x100
  kill "$DAEMON"
  until_true eval '! kill -0 "$WATCHER" 2>/dev/null'
  until_true eval '! pgrep -f "$X/" >/dev/null'
}

@test "a stopped watcher brings a hidden island back" {
  video 0x100; echo 0x100 > "$X/active"
  start_watcher
  until_true hidden
  kill "$WATCHER"
  until_true shown
  until_true eval '! pgrep -f "$X/" >/dev/null'
}

@test "ISLAND_FULLSCREEN_HIDE=0 never watches or hides" {
  video 0x100; echo 0x100 > "$X/active"
  ISLAND_FULLSCREEN_HIDE=0 run timeout 2 "$SCRIPTS/fullscreen" "$DAEMON"
  [ "$status" -eq 0 ]
  [ ! -s "$X/spies.log" ]
  [ "$(calls)" = "" ]
  [ ! -e "$ST/fullscreen" ]
}
