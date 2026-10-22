# tests/alert/screenshot.bats
load helpers

@test "new screenshot images emit a thumbnail alert and other files are ignored" {
  local dir=/home/user/Gambar/Screenshots
  {
    screenshot_event "$dir/Screenshot_2026-10-22.png"
    screenshot_event "$dir/notes.txt"
    screenshot_event "$dir/.Screenshot.png.part"
    screenshot_event "$dir/foto liburan.JPG"
    screenshot_event "$dir/b.jpeg"
  } > "$RESULT"
  [ "$(jq -sc 'map([.kind,.text,.value,.level,.image])' "$RESULT")" = '[["screenshot","Tangkapan layar","Screenshot_2026-10-22.png",-1,"file:///home/user/Gambar/Screenshots/Screenshot_2026-10-22.png"],["screenshot","Tangkapan layar","foto liburan.JPG",-1,"file:///home/user/Gambar/Screenshots/foto%20liburan.JPG"],["screenshot","Tangkapan layar","b.jpeg",-1,"file:///home/user/Gambar/Screenshots/b.jpeg"]]' ]
  [ "$(jq -sr 'map(.icon)|join("|")' "$RESULT")" = $'\U000F0100|\U000F0100|\U000F0100' ]
}

@test "screenshot image is a file URI safe to embed in a CSS url" {
  screenshot_event "/home/user/Layar (1)/it's a\\shot.png" > "$RESULT"
  [ "$(jq -r .value "$RESULT")" = "it's a\\shot.png" ]
  [ "$(jq -r .image "$RESULT")" = 'file:///home/user/Layar%20%281%29/it%27s%20a%5Cshot.png' ]
}

@test "screenshot directory follows ob-screenshot: override, else XDG pictures (\$HOME when unset)" {
  export HOME="$BATS_TEST_TMPDIR/home"
  [ "$(screenshot_dir)" = "$ISLAND_SCREENSHOT_DIR" ]
  unset ISLAND_SCREENSHOT_DIR
  cat > "$BIN/xdg-user-dir" <<'EOF'
#!/usr/bin/env bash
[[ $* == PICTURES ]] || exit 2
cat "$ALERT_FIXTURE/xdg-pictures"
EOF
  chmod +x "$BIN/xdg-user-dir"
  printf '%s\n' "$HOME/Gambar" > "$ALERT_FIXTURE/xdg-pictures"
  [ "$(screenshot_dir)" = "$HOME/Gambar/Screenshots" ]
  printf '%s\n' "$HOME" > "$ALERT_FIXTURE/xdg-pictures"
  [ "$(screenshot_dir)" = "$HOME/Screenshots" ]
  rm "$BIN/xdg-user-dir"
  [ "$(PATH="$BIN" screenshot_dir)" = "$HOME/Screenshots" ]
}
