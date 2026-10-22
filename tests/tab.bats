# tests/tab.bats
setup() {
  load helpers
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run" EXPECTED_CFG="$REPO/eww"
  export FAKE_EWW_LOG="$BATS_TEST_TMPDIR/eww.log" FAKE_WEATHER="$BATS_TEST_TMPDIR/weather"
  export FAKE_TAB="$BATS_TEST_TMPDIR/island_tab" FAKE_NOTIF="$BATS_TEST_TMPDIR/notif_center"
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

@test "resolve picks the first tab in order when nothing is saved" {
  both
  run "$SCRIPTS/tab" resolve
  [ "$status" -eq 0 ]
  [ "$output" = musik ]
  [ "$(calls)" = "" ]
}

@test "resolve reopens the saved tab while it is available" {
  both; saved cuaca
  run "$SCRIPTS/tab" resolve
  [ "$output" = cuaca ]
}

@test "resolve treats paused music as available" {
  music paused; weather; saved musik
  run "$SCRIPTS/tab" resolve
  [ "$output" = musik ]
}

@test "resolve keeps music while the next track loads" {
  music loading; weather; saved musik
  run "$SCRIPTS/tab" resolve
  [ "$output" = musik ]
}

@test "resolve falls back to weather when the music stopped, keeping the saved choice" {
  no_music; weather; saved musik
  run "$SCRIPTS/tab" resolve
  [ "$output" = cuaca ]
  [ "$(cat "$ST/tab")" = musik ]
}

@test "resolve shows music when weather is unavailable" {
  music; no_weather; saved cuaca
  run "$SCRIPTS/tab" resolve
  [ "$output" = musik ]
}

@test "resolve treats a missing media state as no music" {
  weather; saved musik
  run "$SCRIPTS/tab" resolve
  [ "$output" = cuaca ]
}

@test "resolve ignores an unknown saved tab" {
  both; saved kalender
  run "$SCRIPTS/tab" resolve
  [ "$output" = musik ]
}

@test "resolve prefers an explicitly requested available tab without saving it" {
  both; saved cuaca
  run "$SCRIPTS/tab" resolve musik
  [ "$output" = musik ]
  [ "$(cat "$ST/tab")" = cuaca ]
  [ "$(calls)" = "" ]
}

@test "resolve skips a requested tab that is unavailable" {
  no_music; weather; saved musik
  run "$SCRIPTS/tab" resolve musik
  [ "$output" = cuaca ]
}

@test "resolve answers the first tab when nothing is available" {
  no_music; no_weather
  run "$SCRIPTS/tab" resolve
  [ "$status" -eq 0 ]
  [ "$output" = musik ]
}

@test "select saves the tab and shows it" {
  both; shown musik
  run "$SCRIPTS/tab" select cuaca
  [ "$status" -eq 0 ]
  [ "$(cat "$ST/tab")" = cuaca ]
  [ "$(calls)" = 'update island_tab=cuaca' ]
}

@test "select rejects an unknown tab without touching eww or the saved choice" {
  both; saved musik
  run "$SCRIPTS/tab" select kalender
  [ "$status" -eq 2 ]
  [ "$(cat "$ST/tab")" = musik ]
  [ "$(calls)" = "" ]
}

@test "next moves to the following available tab and saves it" {
  both; shown musik
  run "$SCRIPTS/tab" next
  [ "$status" -eq 0 ]
  [ "$(calls)" = 'update island_tab=cuaca' ]
  [ "$(cat "$ST/tab")" = cuaca ]
}

@test "next wraps from the last available tab to the first" {
  both; shown cuaca
  run "$SCRIPTS/tab" next
  [ "$(calls)" = 'update island_tab=musik' ]
  [ "$(cat "$ST/tab")" = musik ]
}

@test "prev wraps from the first available tab to the last" {
  both; shown musik
  run "$SCRIPTS/tab" prev
  [ "$(calls)" = 'update island_tab=cuaca' ]
}

@test "scroll down and up on the header map to next and prev" {
  both; shown musik
  run "$SCRIPTS/tab" down
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_TAB")" = cuaca ]
  rm -f "$ST/tab_at"
  run "$SCRIPTS/tab" up
  [ "$(cat "$FAKE_TAB")" = musik ]
}

@test "next with a single available tab changes nothing" {
  no_music; weather; shown cuaca; saved musik
  run "$SCRIPTS/tab" next
  [ "$status" -eq 0 ]
  [ "$(calls)" = "" ]
  [ "$(cat "$ST/tab")" = musik ]
}

@test "a burst of scroll events switches the tab only once" {
  both; shown musik
  run "$SCRIPTS/tab" next
  run "$SCRIPTS/tab" next
  run "$SCRIPTS/tab" next
  [ "$(calls)" = 'update island_tab=cuaca' ]
}

@test "scrolling again after the burst settles switches again" {
  both; shown musik
  run "$SCRIPTS/tab" next
  echo 0 > "$ST/tab_at"
  run "$SCRIPTS/tab" next
  [ "$(calls)" = $'update island_tab=cuaca\nupdate island_tab=musik' ]
}

@test "clicking a tab is never swallowed by the scroll debounce" {
  both; shown musik
  run "$SCRIPTS/tab" next
  run "$SCRIPTS/tab" select musik
  [ "$(calls)" = $'update island_tab=cuaca\nupdate island_tab=musik' ]
}

@test "unknown commands are rejected" {
  run "$SCRIPTS/tab" explode
  [ "$status" -eq 2 ]
  run "$SCRIPTS/tab"
  [ "$status" -eq 2 ]
  [ "$(calls)" = "" ]
}

@test "the notification tab is offered while the center has entries" {
  no_music; no_weather; notif
  run "$SCRIPTS/tab" resolve
  [ "$output" = notif ]
  no_notif; weather; saved notif
  run "$SCRIPTS/tab" resolve
  [ "$output" = cuaca ]
}

@test "the notification tab comes after music and weather" {
  both; notif; shown cuaca
  run "$SCRIPTS/tab" next
  [ "$(cat "$FAKE_TAB")" = notif ]
  rm -f "$ST/tab_at"
  run "$SCRIPTS/tab" next
  [ "$(cat "$FAKE_TAB")" = musik ]
  run "$SCRIPTS/tab" resolve
  [ "$output" = musik ]
}

@test "select tells the notification center which tab is shown" {
  both; notif
  mkfifo "$ST/notif.fifo"
  exec {notif_fd}<> "$ST/notif.fifo"
  run "$SCRIPTS/tab" select notif
  [ "$status" -eq 0 ]
  IFS= read -r -t 1 -u "$notif_fd" line
  [ "$line" = '@tab notif' ]
  [ "$(calls)" = 'update island_tab=notif' ]
}

@test "the to-do tab is offered while its list listener runs, even with nothing else" {
  no_music; no_weather; no_notif
  run "$SCRIPTS/tab" resolve
  [ "$output" = musik ]
  mkfifo "$ST/todo.fifo"
  run "$SCRIPTS/tab" resolve
  [ "$output" = tugas ]
  run "$SCRIPTS/tab" select tugas
  [ "$status" -eq 0 ]
  [ "$(cat "$ST/tab")" = tugas ]
}

@test "the to-do tab comes after notifications" {
  both; notif; shown notif; mkfifo "$ST/todo.fifo"
  run "$SCRIPTS/tab" next
  [ "$(cat "$FAKE_TAB")" = tugas ]
  rm -f "$ST/tab_at"
  run "$SCRIPTS/tab" next
  [ "$(cat "$FAKE_TAB")" = musik ]
}
