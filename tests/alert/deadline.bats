# tests/alert/deadline.bats: to-do deadline reminders.
load helpers

at() { date -d "$1" +%s; }
add_due() { ISLAND_NOW=$(at "$1") "$SCRIPTS/todo" add "$2" --due "$(at "$3")"; }
tick() { ISLAND_NOW=$(at "$1") deadline_snapshot; }
notified() { cat "$ALERT_FIXTURE/notified" 2>/dev/null || :; }

prepare() {
  export TZ=Asia/Jakarta
  unset ISLAND_DEADLINE_EVE ISLAND_DEADLINE_DAY
  cat > "$BIN/notify-send" <<'EOF'
#!/usr/bin/env bash
app=''
while [[ $1 == -* ]]; do
  case $1 in -a) app=$2; shift 2 ;; --) shift; break ;; *) shift ;; esac
done
printf '%s|%s|%s\n' "$app" "$1" "${2:-}" >> "$ALERT_FIXTURE/notified"
EOF
  chmod +x "$BIN/notify-send"
}

@test "a deadline reminds the day before at 09:00 and on the day at 09:00, once each" {
  prepare
  add_due '2026-10-21 08:00' 'Laporan Q3' '2026-10-22 17:00'
  tick '2026-10-21 08:59'
  [ -z "$(notified)" ]
  tick '2026-10-21 09:00'
  tick '2026-10-21 12:00'
  tick '2026-10-22 08:59'
  tick '2026-10-22 09:00'
  tick '2026-10-22 16:59'
  [ "$(notified)" = $'Tugas|Deadline besok · 17:00|Laporan Q3\nTugas|Deadline hari ini · 17:00|Laporan Q3' ]
}

@test "reminders missed while away collapse into the latest one" {
  prepare
  add_due '2026-10-20 08:00' a '2026-10-22 17:00'
  tick '2026-10-22 10:00'
  tick '2026-10-22 11:00'
  [ "$(notified)" = 'Tugas|Deadline hari ini · 17:00|a' ]
}

@test "a missed eve reminder caught on the deadline day says hari ini" {
  prepare
  add_due '2026-10-20 08:00' a '2026-10-22 17:00'
  tick '2026-10-22 08:00'
  [ "$(notified)" = 'Tugas|Deadline hari ini · 17:00|a' ]
}

@test "done items, passed deadlines and reminders already past when set stay silent" {
  prepare
  add_due '2026-10-21 10:00' diset-telat '2026-10-22 17:00'
  add_due '2026-10-20 08:00' selesai '2026-10-22 17:00'
  ISLAND_NOW=$(at '2026-10-20 08:00') "$SCRIPTS/todo" toggle 2
  add_due '2026-10-20 08:00' lampau '2026-10-21 08:00'
  tick '2026-10-21 12:00'
  [ -z "$(notified)" ]
}

@test "changing a deadline re-arms its reminders" {
  prepare
  add_due '2026-10-20 08:00' a '2026-10-21 17:00'
  tick '2026-10-21 09:30'
  ISLAND_NOW=$(at '2026-10-21 10:00') "$SCRIPTS/todo" set-due 1 "$(at '2026-10-23 17:00')"
  tick '2026-10-22 09:00'
  [ "$(notified)" = $'Tugas|Deadline hari ini · 17:00|a\nTugas|Deadline besok · 17:00|a' ]
}

@test "reminder times follow the environment and an empty one is off" {
  prepare
  export ISLAND_DEADLINE_EVE='' ISLAND_DEADLINE_DAY=07:30
  add_due '2026-10-20 08:00' a '2026-10-22 17:00'
  tick '2026-10-21 12:00'
  tick '2026-10-22 07:30'
  [ "$(notified)" = 'Tugas|Deadline hari ini · 17:00|a' ]
}

@test "reminder bodies keep the item text exactly" {
  prepare
  add_due '2026-10-21 08:00' 'Periksa C:\temp dan "kutip"' '2026-10-22 17:00'
  tick '2026-10-21 09:00'
  [ "$(notified)" = 'Tugas|Deadline besok · 17:00|Periksa C:\temp dan "kutip"' ]
}

@test "a reminder another writer already claimed is not sent again" {
  prepare
  add_due '2026-10-21 08:00' a '2026-10-22 17:00'
  local stale file="$XDG_DATA_HOME/eww-island/todo.json"
  stale=$(cat "$file")
  jq -c '.items[0].reminded = ["eve"]' "$file" > "$file.new" && mv "$file.new" "$file"
  store_read() { printf '%s\n' "$stale"; }
  tick '2026-10-21 09:00'
  [ -z "$(notified)" ]
}
