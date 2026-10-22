# tests/launcher.bats
setup() {
  load helpers
  export HOME="$BATS_TEST_TMPDIR/home" XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache" XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run" XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN" "$HOME"
  printf '#!/usr/bin/env bash\necho "$*" >> "%s/dunstify.log"\n' "$BATS_TEST_TMPDIR" > "$BIN/dunstify"
  printf '#!/usr/bin/env bash\necho "$*" >> "%s/eww.log"\n' "$BATS_TEST_TMPDIR" > "$BIN/eww"
  printf '#!/usr/bin/env bash\necho "$*" >> "%s/dunstctl.log"\nexit "${FAKE_DUNSTCTL_STATUS:-0}"\n' "$BATS_TEST_TMPDIR" > "$BIN/dunstctl"
  chmod +x "$BIN/dunstify" "$BIN/eww" "$BIN/dunstctl"
  PATH="$BIN:$PATH"
}

@test "a missing island config notifies and starts no daemon" {
  run "$REPO/openbox/island.sh"
  [ "$status" -eq 1 ]
  grep -q 'island gagal' "$BATS_TEST_TMPDIR/dunstify.log"
  [ ! -e "$BATS_TEST_TMPDIR/eww.log" ]
}

delayed_eww() {
  mkdir -p "$HOME/.config/eww-island" "$XDG_RUNTIME_DIR/eww-island"
  touch "$HOME/.config/eww-island/eww.yuck"
  ln -s "$REPO/eww/dunst-osd.conf" "$HOME/.config/eww-island/dunst-osd.conf"
  export FAKE_LAUNCH_STATE="$BATS_TEST_TMPDIR/shutdown" FAKE_LAUNCH_LOG="$BATS_TEST_TMPDIR/events"
  export FAKE_LAUNCH_PALETTE="$BATS_TEST_TMPDIR/daemon-colors.scss"
  cat > "$BIN/eww" <<'EOF'
#!/usr/bin/env bash
[[ $1 == --config && $2 == "$HOME/.config/eww-island" ]] || exit 2
shift 2
case $1 in
  kill) echo "${FAKE_SHUTDOWN_POLLS:-3}" > "$FAKE_LAUNCH_STATE"; echo kill >> "$FAKE_LAUNCH_LOG" ;;
  ping)
    read -r remaining < "$FAKE_LAUNCH_STATE"
    if (( remaining > 0 )); then
      echo $((remaining - 1)) > "$FAKE_LAUNCH_STATE"
      echo stopping >> "$FAKE_LAUNCH_LOG"
    elif (( remaining == 0 )); then
      echo unreachable >> "$FAKE_LAUNCH_LOG"; exit 1
    elif (( remaining < -1 )); then
      # A daemon that is still starting does not answer yet.
      echo $((remaining + 1)) > "$FAKE_LAUNCH_STATE"
      echo starting >> "$FAKE_LAUNCH_LOG"; exit 1
    fi ;;
  daemon)
    if [[ -r "$HOME/.config/eww-island/_colors.scss" ]]; then
      cp "$HOME/.config/eww-island/_colors.scss" "$FAKE_LAUNCH_PALETTE"
    fi
    echo daemon >> "$FAKE_LAUNCH_LOG"
    echo $(( -1 - ${FAKE_STARTUP_POLLS:-0} )) > "$FAKE_LAUNCH_STATE" ;;
  open) echo "$*" >> "$FAKE_LAUNCH_LOG" ;;
esac
EOF
  chmod +x "$BIN/eww"
}

@test "restart waits for shutdown before starting the daemon and opening island" {
  delayed_eww
  run "$REPO/openbox/island.sh"
  [ "$status" -eq 0 ]
  [ "$(grep -E '^(unreachable|daemon|open)' "$FAKE_LAUNCH_LOG" | uniq)" = $'unreachable\ndaemon\nopen island' ]
}

@test "a daemon slow to answer still opens the island and installs the OSD drop-in" {
  delayed_eww
  export FAKE_STARTUP_POLLS=70
  run "$REPO/openbox/island.sh"
  [ "$status" -eq 0 ]
  grep -qx 'open island' "$FAKE_LAUNCH_LOG"
  cmp "$REPO/eww/dunst-osd.conf" "$XDG_CONFIG_HOME/dunst/dunstrc.d/50-eww-island-osd.conf"
  [ ! -e "$BATS_TEST_TMPDIR/dunstify.log" ]
}

@test "stop kills only the island config and removes state even when already stopped" {
  delayed_eww
  run "$REPO/openbox/island.sh" stop
  [ "$status" -eq 0 ]
  [ ! -d "$XDG_RUNTIME_DIR/eww-island" ]
  [ "$(uniq "$FAKE_LAUNCH_LOG")" = $'kill\nstopping\nunreachable' ]
  export FAKE_SHUTDOWN_POLLS=0
  run "$REPO/openbox/island.sh" stop
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/dunstify.log" ]
}

@test "a daemon that never stops fails without starting a replacement" {
  delayed_eww
  export FAKE_SHUTDOWN_POLLS=100
  run "$REPO/openbox/island.sh"
  [ "$status" -eq 1 ]
  [[ $output == *"daemon lama tidak berhenti"* ]]
  ! grep -qx daemon "$FAKE_LAUNCH_LOG"
  [ -d "$XDG_RUNTIME_DIR/eww-island" ]
}

@test "launch replaces a stale island palette with the bar palette before daemon start" {
  delayed_eww
  mkdir -p "$HOME/.config/eww"
  printf '%s\n' '$bg: #dead00;' > "$HOME/.config/eww-island/_colors.scss"
  cat > "$HOME/.config/eww/_colors.scss" <<'EOF'
// active bar theme
$bg: #131519;
$fg: #d8d8d8;
$alt-bg: #292d36;
$accent: #88c0d0;
$blue: #81A1C1;
$font: "Sans";
EOF
  run "$REPO/openbox/island.sh"
  [ "$status" -eq 0 ]
  cmp "$HOME/.config/eww/_colors.scss" "$HOME/.config/eww-island/_colors.scss"
  cmp "$HOME/.config/eww/_colors.scss" "$FAKE_LAUNCH_PALETTE"
}

@test "launch without a bar palette writes all island palette keys before daemon start" {
  delayed_eww
  run "$REPO/openbox/island.sh"
  [ "$status" -eq 0 ]
  local key
  for key in bg fg alt-bg accent blue yellow green font; do
    grep -Eq "^\\\$$key: [^;]+;" "$HOME/.config/eww-island/_colors.scss"
    grep -Eq "^\\\$$key: [^;]+;" "$FAKE_LAUNCH_PALETTE"
  done
  cmp "$HOME/.config/eww-island/_colors.scss" "$FAKE_LAUNCH_PALETTE"
}

@test "launch installs the island OSD drop-in and reloads dunst after opening" {
  delayed_eww
  run "$REPO/openbox/island.sh"
  [ "$status" -eq 0 ]
  local dropin="$XDG_CONFIG_HOME/dunst/dunstrc.d/50-eww-island-osd.conf"
  [ -f "$dropin" ]
  cmp "$REPO/eww/dunst-osd.conf" "$dropin"
  [ "$(cat "$BATS_TEST_TMPDIR/dunstctl.log")" = reload ]
}

@test "stop removes the island OSD drop-in and reloads dunst" {
  delayed_eww
  local dropin="$XDG_CONFIG_HOME/dunst/dunstrc.d/50-eww-island-osd.conf"
  mkdir -p "${dropin%/*}"
  printf 'old island rules\n' > "$dropin"
  run "$REPO/openbox/island.sh" stop
  [ "$status" -eq 0 ]
  [ ! -e "$dropin" ]
  [ "$(cat "$BATS_TEST_TMPDIR/dunstctl.log")" = reload ]
}

@test "restart removes old OSD suppression before installing the current drop-in" {
  delayed_eww
  local dropin="$XDG_CONFIG_HOME/dunst/dunstrc.d/50-eww-island-osd.conf"
  mkdir -p "${dropin%/*}"
  printf 'old island rules\n' > "$dropin"
  run "$REPO/openbox/island.sh"
  [ "$status" -eq 0 ]
  cmp "$REPO/eww/dunst-osd.conf" "$dropin"
  [ "$(cat "$BATS_TEST_TMPDIR/dunstctl.log")" = $'reload\nreload' ]
}

@test "launch without dunstctl succeeds without installing OSD suppression" {
  delayed_eww
  rm "$BIN/dunstctl"
  local command
  for command in bash sleep rm mktemp cp cat mv mkdir setsid; do
    ln -s "$(command -v "$command")" "$BIN/$command"
  done
  run env PATH="$BIN" "$REPO/openbox/island.sh"
  [ "$status" -eq 0 ]
  [ ! -e "$XDG_CONFIG_HOME/dunst/dunstrc.d/50-eww-island-osd.conf" ]
  [ ! -e "$BATS_TEST_TMPDIR/dunstctl.log" ]
}

@test "dunst reload failure does not fail launch or stop" {
  delayed_eww
  export FAKE_DUNSTCTL_STATUS=1
  run "$REPO/openbox/island.sh"
  [ "$status" -eq 0 ]
  run "$REPO/openbox/island.sh" stop
  [ "$status" -eq 0 ]
  [ ! -e "$XDG_CONFIG_HOME/dunst/dunstrc.d/50-eww-island-osd.conf" ]
}
