# tests/tab/common.bash: fake eww and tab availability fixtures for scripts/tab.
setup() {
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run" EXPECTED_CFG="$REPO/eww"
  export FAKE_EWW_LOG="$BATS_TEST_TMPDIR/eww.log" FAKE_WEATHER="$BATS_TEST_TMPDIR/weather"
  export FAKE_TAB="$BATS_TEST_TMPDIR/island_tab" FAKE_NOTIF="$BATS_TEST_TMPDIR/notif_center"
  # No shortcuts config unless a test writes one.
  export ISLAND_SHORTCUTS="$BATS_TEST_TMPDIR/shortcuts"
  ST="$XDG_RUNTIME_DIR/eww-island"; mkdir -p "$ST"
  : > "$FAKE_EWW_LOG"
  # Fake eww: `get` answers weather and island_tab without logging; other calls are logged.
  cat > "$BIN/eww" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == --config && $2 == "$EXPECTED_CFG" ]]; then shift 2; else echo "bad config: $*" >> "$FAKE_EWW_LOG"; exit 1; fi
case $1 in
  get)
    case $2 in
      weather) cat "$FAKE_WEATHER" 2>/dev/null ;;
      island_tab) cat "$FAKE_TAB" 2>/dev/null ;;
      notif_center) cat "$FAKE_NOTIF" 2>/dev/null ;;
    esac
    exit 0 ;;
  update)
    for kv in "${@:2}"; do [[ $kv == island_tab=* ]] && printf '%s\n' "${kv#*=}" > "$FAKE_TAB"; done ;;
esac
printf '%s\n' "$*" >> "$FAKE_EWW_LOG"
EOF
  chmod +x "$BIN/eww"
  PATH="$BIN:$PATH"
}
calls() { cat "$FAKE_EWW_LOG"; }
music() { printf '{"state":"%s","player":"ytm_player","title":"Lagu","artist":"Artis"}\n' "${1:-playing}" > "$ST/media.json"; }
no_music() { printf '{"state":"none","player":"","title":"","artist":""}\n' > "$ST/media.json"; }
weather() { printf '{"ok":true,"temp":"31°"}\n' > "$FAKE_WEATHER"; }
no_weather() { printf '{"ok":false,"temp":""}\n' > "$FAKE_WEATHER"; }
saved() { printf '%s\n' "$1" > "$ST/tab"; }
shown() { printf '%s\n' "$1" > "$FAKE_TAB"; }
both() { music; weather; }
notif() { printf '{"total":%s,"unread":0,"rows":[]}\n' "${1:-2}" > "$FAKE_NOTIF"; }
no_notif() { notif 0; }
shortcuts() { printf 'x | Kunci | true\n' > "$ISLAND_SHORTCUTS"; }
