# tests/alert/meeting.bats: meeting reminders from the agenda.
load helpers

at() { date -d "$1" +%s; }
tick() { ISLAND_NOW=$(at "$1") meeting_event tick; }
notified() { cat "$ALERT_FIXTURE/notified" 2>/dev/null || :; }
opened() { cat "$ALERT_FIXTURE/opened" 2>/dev/null || :; }

prepare() {
  export TZ=Asia/Jakarta
  unset ISLAND_MEETING_BEFORE ISLAND_MEETING_AUTO
  mkdir -p "$ISLAND_STATE"
  cat > "$BIN/notify-send" <<'EOF'
#!/usr/bin/env bash
app=''
while [[ $1 == -* ]]; do
  case $1 in -a) app=$2; shift 2 ;; --) shift; break ;; *) shift ;; esac
done
printf '%s|%s|%s\n' "$app" "$1" "${2:-}" >> "$ALERT_FIXTURE/notified"
EOF
  chmod +x "$BIN/notify-send"
  # The island itself is out of scope here: record what would open.
  meeting_open() { printf 'open %s\n' "$1" >> "$ALERT_FIXTURE/opened"; }
}

# agenda TITLE TIME...: the agenda file with one 30-minute row per pair, id = "id-" + TITLE.
agenda() {
  local rows='[]'
  while (( $# )); do
    rows=$(jq -c --arg t "$1" --argjson s "$(at "$2")" \
      '. + [{id: ("id-" + $t), title: $t, start: $s, end: ($s + 1800)}]' <<< "$rows")
    shift 2
  done
  jq -nc --argjson rows "$rows" '{ok: true, rows: $rows}' > "$ISLAND_STATE/agenda.json"
}

@test "a meeting reminds ten minutes ahead and at its start, once each, opening the Kalender tab" {
  prepare
  agenda 'Weekly Report' '2026-10-21 10:00'
  tick '2026-10-21 09:49'
  [ -z "$(notified)" ]
  tick '2026-10-21 09:50'
  tick '2026-10-21 09:55'
  tick '2026-10-21 10:00'
  tick '2026-10-21 10:03'
  [ "$(notified)" = $'Kalender|Meeting 10 menit lagi · 10:00|Weekly Report\nKalender|Meeting dimulai · 10:00|Weekly Report' ]
  [ "$(opened)" = $'open 10\nopen 10' ]
}

@test "a late wake-up shows only the start, and nothing fires five minutes in" {
  prepare
  agenda 'Standup' '2026-10-21 10:00' 'Sync' '2026-10-21 09:55'
  tick '2026-10-21 10:01'
  [ "$(notified)" = 'Kalender|Meeting dimulai · 10:00|Standup' ]
}

@test "the lead time and how long the tab stays open follow the environment; an empty lead time is off" {
  prepare
  export ISLAND_MEETING_BEFORE=5 ISLAND_MEETING_AUTO=20
  agenda 'Review' '2026-10-21 10:00'
  tick '2026-10-21 09:54'
  tick '2026-10-21 09:55'
  [ "$(notified)" = 'Kalender|Meeting 5 menit lagi · 10:00|Review' ]
  [ "$(opened)" = 'open 20' ]
  export ISLAND_MEETING_BEFORE=''
  agenda 'Retro' '2026-10-21 11:00'
  : > "$ALERT_FIXTURE/notified"
  tick '2026-10-21 10:50'
  tick '2026-10-21 11:00'
  [ "$(notified)" = 'Kalender|Meeting dimulai · 11:00|Retro' ]
}

@test "titles reach the notification verbatim; no agenda or a broken one stays silent" {
  prepare
  tick '2026-10-21 10:00'
  printf 'not json' > "$ISLAND_STATE/agenda.json"
  tick '2026-10-21 10:00'
  [ -z "$(notified)" ]
  agenda 'Rapat C:\tim "inti"' '2026-10-21 10:00'
  tick '2026-10-21 10:00'
  [ "$(notified)" = 'Kalender|Meeting dimulai · 10:00|Rapat C:\tim "inti"' ]
}

@test "two meetings starting together both remind" {
  prepare
  agenda 'A' '2026-10-21 10:00' 'B' '2026-10-21 10:00'
  tick '2026-10-21 10:00'
  [ "$(notified)" = $'Kalender|Meeting dimulai · 10:00|A\nKalender|Meeting dimulai · 10:00|B' ]
  [ "$(opened)" = $'open 10\nopen 10' ]
}

@test "a monitor baseline stays silent and leaves the first tick unclaimed" {
  prepare
  agenda 'Standup' '2026-10-21 10:00'
  ISLAND_NOW=$(at '2026-10-21 10:00') alert_source=meeting source_baseline
  [ -z "$(notified)" ]
  [ -z "$(opened)" ]
  tick '2026-10-21 10:00'
  tick '2026-10-21 10:00'
  [ "$(notified)" = 'Kalender|Meeting dimulai · 10:00|Standup' ]
  [ "$(opened)" = 'open 10' ]
}
