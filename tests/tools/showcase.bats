# tests/tools/showcase.bats
setup() {
  SHOWCASE="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/tools/showcase"
  T=$BATS_TEST_TMPDIR
  CFG="$T/config"
  mkdir -p "$CFG/yuck" "$CFG/scripts" "$T/bin" "$T/samples/assets" "$T/out/screenshots"
  printf '(include "yuck/vars.yuck")\n' > "$CFG/eww.yuck"
  printf '(deflisten media :initial %s "scripts/media")\n' "'{\"state\":\"none\"}'" > "$CFG/yuck/vars.yuck"
  printf '.pill { color: red; }\n' > "$CFG/eww.scss"
  printf '#!/bin/sh\nexec real-island "$@"\n' > "$CFG/scripts/island"
  cp -r "$CFG" "$T/pristine"

  printf 'window=island\nmedia={"state":"playing"}\n' > "$T/samples/pill-music.vars"
  printf 'window=island-expanded\ntab=cuaca\nweather={"ok":true}\n' > "$T/samples/card-weather.vars"
  printf 'window=island\nnotify={"active":true,"summary":"Linus"}\n' > "$T/samples/pill-notify.vars"
  : > "$T/out/screenshots/gone.png"

  export LOG="$T/log" SEEN="$T/seen" PREVIEW_SETTLE=0 SHOWCASE_PACE=0 XDG_CACHE_HOME="$T/cache"
  export SHOWCASE_CONFIG=$CFG SHOWCASE_SAMPLES="$T/samples" DISPLAY=:7
  mkdir -p "$XDG_CACHE_HOME/eww" "$SEEN"
  # Fake eww: logs each call, snapshots each config copy at daemon start, leaves a socket and log.
  cat > "$T/bin/eww" <<'EOF'
#!/usr/bin/env bash
[[ $1 == --config ]] || { echo "eww without --config" >> "$LOG"; exit 9; }
cfg=$2; shift 2
printf '%s|%s|%s\n' "$cfg" "$XDG_RUNTIME_DIR" "$*" >> "$LOG"
case $1 in
  daemon)
    cp -r "$cfg" "$SEEN/${cfg##*/}"
    : > "$XDG_RUNTIME_DIR/eww-server_f00d"; : > "$XDG_CACHE_HOME/eww/eww_f00d.log" ;;
  open) [[ -z ${FAKE_OPEN_FAIL:-} ]] || exit 1 ;;
esac
exit 0
EOF
  cat > "$T/bin/import" <<'EOF'
#!/usr/bin/env bash
printf 'import|%s\n' "$*" >> "$LOG"
: > "${!#}"
EOF
  # Fake ffmpeg: the x11grab recording runs until TERM; a conversion writes its output.
  cat > "$T/bin/ffmpeg" <<'EOF'
#!/usr/bin/env bash
printf 'ffmpeg|%s\n' "$*" >> "$LOG"
[[ -z ${FAKE_FFMPEG_FAIL:-} ]] || exit 1
if [[ " $* " == *' x11grab '* ]]; then
  printf raw > "${!#}"
  trap 'exit 0' TERM
  while :; do sleep 0.05; done
fi
printf gif > "${!#}"
EOF
  chmod +x "$T/bin/eww" "$T/bin/import" "$T/bin/ffmpeg"
  PATH="$T/bin:$PATH"
}

# copies: every config copy a daemon was started on.
copies() { awk -F'|' '$3 == "daemon" { print $1 }' "$LOG"; }
# demo_copy: the copy with animations on.
demo_copy() {
  local dir
  for dir in "$SEEN"/*; do grep -q 'animation: none' "$dir/eww.scss" || printf '%s\n' "$dir"; done
}
updates() { awk -F'|' 'index($3, "update ") == 1 { print $3 }' "$LOG"; }

@test "renders one PNG per sample, drops stale ones and records the demo GIF" {
  run "$SHOWCASE" "$T/out"
  [ "$status" -eq 0 ]
  [ "$(ls "$T/out/screenshots")" = $'card-weather.png\npill-music.png\npill-notify.png' ]
  [ "$(cat "$T/out/demo.gif")" = gif ]
  [ "$(grep -c '^import|' "$LOG")" -eq 3 ]
  [ "$(copies | wc -l)" -eq 4 ]
  grep -q 'ffmpeg|.*-f x11grab .*-video_size 520x230 .*-i :7+700,300 ' "$LOG"
  grep -q 'ffmpeg|.*palettegen.*paletteuse.*demo.gif$' "$LOG"
  [ "$(grep -c 'without --config' "$LOG")" -eq 0 ]
  diff -r "$T/pristine" "$CFG"
  for dir in "$SEEN"/*; do grep -qF 'background-image: linear-gradient(' "$dir/eww.scss"; done
}

@test "the demo runs with animations on, drives the card itself and reuses the samples" {
  run "$SHOWCASE" "$T/out"
  [ "$status" -eq 0 ]
  demo=$(demo_copy)
  [ "$(printf '%s\n' "$demo" | wc -l)" -eq 1 ]
  [ "$(cat "$demo/scripts/island")" = '#!/bin/sh' ]
  grep -q 'defwindow preview-backdrop' "$demo/eww.yuck"
  updates | grep -q '^update island_tab=pintasan$'
  updates | grep -q '"kind":"volume".*"level":65'
  updates | grep -qF 'notify={"active":true,"summary":"Linus"}'
  updates | grep -q '^update viz=\['
}

@test "a failing render stops before the demo and leaves nothing behind" {
  FAKE_OPEN_FAIL=1 run "$SHOWCASE" "$T/out"
  [ "$status" -ne 0 ]
  [ "$(grep -c '^ffmpeg|' "$LOG")" -eq 0 ]
  [ -n "$(copies)" ]
  for dir in $(copies); do [ ! -e "$dir" ]; [ ! -e "$dir.run" ]; done
  [ ! -e "$XDG_CACHE_HOME/eww/eww_f00d.log" ]
}

@test "a failing recording still kills the daemon and removes the temp dirs" {
  FAKE_FFMPEG_FAIL=1 run "$SHOWCASE" "$T/out"
  [ "$status" -ne 0 ]
  [ ! -e "$T/out/demo.gif" ]
  demo=$(copies | tail -n 1)
  awk -F'|' -v d="$demo" '$1 == d && $3 == "kill"' "$LOG" | grep -q kill
  [ ! -e "$demo" ]
  [ ! -e "$demo.run" ]
  raw=$(awk -F'|' '$1 == "ffmpeg" { print $NF }' "$LOG" | awk '{ print $NF }')
  [[ $raw == /tmp/island-showcase.*/demo.mkv ]]
  [ ! -e "${raw%/*}" ]
}

@test "bad arguments are refused before anything starts" {
  run "$SHOWCASE"
  [ "$status" -eq 2 ]
  SHOWCASE_CONFIG="$T/none" run "$SHOWCASE" "$T/out"
  [ "$status" -eq 2 ]
  [ ! -e "$LOG" ]
}
