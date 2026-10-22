# tests/tools/preview.bats
setup() {
  PREVIEW="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/tools/preview"
  T=$BATS_TEST_TMPDIR
  CFG="$T/config"
  mkdir -p "$CFG/yuck" "$T/bin" "$T/samples/assets"
  printf '(include "yuck/vars.yuck")\n(include "yuck/win.yuck")\n' > "$CFG/eww.yuck"
  cat > "$CFG/yuck/vars.yuck" <<'EOF'
(deflisten media :initial '{"state":"none","title":""}' "scripts/media")
(defpoll pos :interval "1s" :initial '{"pos":0}' :run-while island_reveal "scripts/position")
(deflisten bare "scripts/bare")
(defvar island_tab "musik")
EOF
  cat > "$CFG/yuck/win.yuck" <<'EOF'
(defwindow island
  :geometry (geometry :x "0px" :y "0px" :width "508px" :height "44px" :anchor "top center")
  (label :text "x"))
(defwindow island-expanded
  :geometry (geometry :x "0px" :y "0px" :width "508px" :height "218px" :anchor "top center")
  (label :text "y"))
EOF
  printf '.pill { color: red; }\n' > "$CFG/eww.scss"
  cp -r "$CFG" "$T/pristine"

  printf 'window=island\nmedia={"state":"playing","art":"@ASSETS@/cover.png"}\n' > "$T/samples/pill.vars"
  printf 'window=island-expanded\ntab=cuaca\nweather={"ok":true}\n' > "$T/samples/card.vars"

  export LOG="$T/log" SEEN="$T/seen" PREVIEW_SETTLE=0 XDG_CACHE_HOME="$T/cache"
  mkdir -p "$XDG_CACHE_HOME/eww"
  : > "$XDG_CACHE_HOME/eww/eww_other.log"
  # Fake eww: logs each call with its runtime dir, snapshots the config copy at daemon start
  # and leaves a socket plus its log like the real daemon.
  cat > "$T/bin/eww" <<'EOF'
#!/usr/bin/env bash
[[ $1 == --config ]] || { echo "eww without --config" >> "$LOG"; exit 9; }
cfg=$2; shift 2
printf '%s|%s|%s\n' "$cfg" "$XDG_RUNTIME_DIR" "$*" >> "$LOG"
case $1 in
  daemon)
    cp -r "$cfg" "$SEEN"; stat -c %a "$XDG_RUNTIME_DIR" > "$SEEN.mode"
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
  chmod +x "$T/bin/eww" "$T/bin/import"
  PATH="$T/bin:$PATH"
}

# calls VERB: the logged arguments of every eww call starting with VERB.
calls() { awk -F'|' -v v="$1" 'index($3, v) == 1 { print $3 }' "$LOG"; }
copy_dir() { awk -F'|' 'NR == 1 { print $1 }' "$LOG"; }
run_dir() { awk -F'|' 'NR == 1 { print $2 }' "$LOG"; }

@test "renders the pill from a private copy and leaves CONFIG_DIR untouched" {
  run "$PREVIEW" "$CFG" "$T/samples/pill.vars" "$T/out.png"
  [ "$status" -eq 0 ]
  [ -f "$T/out.png" ]
  diff -r "$T/pristine" "$CFG"
  [[ $(copy_dir) == /tmp/island-preview.* ]]
  [[ $(run_dir) != "${XDG_RUNTIME_DIR:-}" ]]
  [ "$(cat "$SEEN.mode")" = 700 ]
  [[ $(calls update) == *"media={\"state\":\"playing\",\"art\":\"$T/samples/assets/cover.png\"}"* ]]
  [ "$(calls open)" = $'open preview-backdrop\nopen island' ]
  grep -q 'import|-window root -crop 520x46+700+300 ' "$LOG"
}

@test "the copy has only defvars, a backdrop, no animations and windows moved down" {
  run "$PREVIEW" "$CFG" "$T/samples/pill.vars" "$T/out.png"
  [ "$status" -eq 0 ]
  ! grep -rqE 'deflisten|defpoll' "$SEEN"
  grep -qF "(defvar media '{\"state\":\"none\",\"title\":\"\"}')" "$SEEN/yuck/vars.yuck"
  grep -qF "(defvar pos '{\"pos\":0}')" "$SEEN/yuck/vars.yuck"
  grep -q 'animation: none' "$SEEN/eww.scss"
  grep -q 'defwindow preview-backdrop' "$SEEN/eww.yuck"
  grep -qF '.preview-backdrop { background-color: #808080; }' "$SEEN/eww.scss"
  grep -qF '(defvar bare "")' "$SEEN/yuck/vars.yuck"
  [ "$(grep -c ':y "300px"' "$SEEN/yuck/win.yuck")" -eq 2 ]
  ! grep -q ':y "0px"' "$SEEN/yuck/win.yuck"
}

@test "PREVIEW_BACKDROP sets a colour or, as background-image, a gradient" {
  PREVIEW_BACKDROP='#1e2127' run "$PREVIEW" "$CFG" "$T/samples/pill.vars" "$T/out.png"
  [ "$status" -eq 0 ]
  grep -qF '.preview-backdrop { background-color: #1e2127; }' "$SEEN/eww.scss"
  rm -rf "$SEEN" "$SEEN.mode"
  PREVIEW_BACKDROP='linear-gradient(#333, #111)' run "$PREVIEW" "$CFG" "$T/samples/pill.vars" "$T/out.png"
  [ "$status" -eq 0 ]
  grep -qF '.preview-backdrop { background-image: linear-gradient(#333, #111); }' "$SEEN/eww.scss"
}

@test "the expanded card reveals the sample's tab after opening and crops the card" {
  run "$PREVIEW" "$CFG" "$T/samples/card.vars" "$T/out.png"
  [ "$status" -eq 0 ]
  update=$(calls update)
  [[ $update == *'weather={"ok":true}'* ]]
  [[ $update == *island_tab=cuaca* ]]
  [[ $update == *island_reveal=true* ]]
  [ "$(calls open)" = $'open preview-backdrop\nopen island-expanded' ]
  [ "$(awk -F'|' '$3 ~ /^open/ { n = NR } END { print n }' "$LOG")" -lt "$(awk -F'|' '$3 ~ /^update/ { print NR }' "$LOG")" ]
  grep -q 'import|-window root -crop 520x230+700+300 ' "$LOG"
}

@test "a failing open still kills the daemon and removes the temp dirs" {
  FAKE_OPEN_FAIL=1 run "$PREVIEW" "$CFG" "$T/samples/pill.vars" "$T/out.png"
  [ "$status" -ne 0 ]
  [ -n "$(calls kill)" ]
  [ ! -e "$(copy_dir)" ]
  [ ! -e "$(run_dir)" ]
  [ ! -e "$XDG_CACHE_HOME/eww/eww_f00d.log" ]
  [ ! -e "$T/out.png" ]
  diff -r "$T/pristine" "$CFG"
}

@test "temp dirs and the daemon's log are removed after a successful render too" {
  run "$PREVIEW" "$CFG" "$T/samples/pill.vars" "$T/out.png"
  [ "$status" -eq 0 ]
  [ -n "$(calls kill)" ]
  [ ! -e "$(copy_dir)" ]
  [ ! -e "$(run_dir)" ]
  [ ! -e "$XDG_CACHE_HOME/eww/eww_f00d.log" ]
  [ -e "$XDG_CACHE_HOME/eww/eww_other.log" ]
}

@test "bad arguments and samples are refused before anything starts" {
  run "$PREVIEW" "$CFG" "$T/samples/pill.vars"
  [ "$status" -eq 2 ]
  printf 'window=bar\n' > "$T/samples/bad.vars"
  run "$PREVIEW" "$CFG" "$T/samples/bad.vars" "$T/out.png"
  [ "$status" -eq 2 ]
  [ ! -e "$LOG" ]
}
