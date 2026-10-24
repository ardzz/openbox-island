# tests/prep/template.bats: reading, matching, due times and saving prep templates.
load common
bats_require_minimum_version 1.5.0
# --- prep_templates: parsing ------------------------------------------------

@test "parse skips comments and blanks and reads pattern, before and trimmed items" {
  prep_write '# komen' '' '   ' '  # komentar menjorok' \
    'Weekly Report | 2j | Report progres; Plan minggu depan;'
  run --separate-stderr prep_templates
  [ "$status" -eq 0 ]
  [ "$output" = '[{"pattern":"weekly report","before":"2j","items":["Report progres","Plan minggu depan"],"line":5}]' ]
  [ "$stderr" = '' ]
}

@test "parse lowercases the pattern, keeps an empty before and drops empty items" {
  prep_write 'Standup HARIAN | | Cek blokir;;  ; Siapkan update ;'
  run prep_templates
  [ "$status" -eq 0 ]
  [ "$output" = '[{"pattern":"standup harian","before":"","items":["Cek blokir","Siapkan update"],"line":1}]' ]
}

@test "parse without a file is an empty array" {
  prep_write
  run --separate-stderr prep_templates
  [ "$status" -eq 0 ]
  [ "$output" = '[]' ]
  [ "$stderr" = '' ]
}

@test "bad lines are skipped with prep: baris N dilewati on stderr" {
  prep_write 'Weekly Report | 2j | Report progres' 'x | 5x | a' ' | | a' 'y | |'
  run --separate-stderr prep_templates
  [ "$status" -eq 0 ]
  [ "$output" = '[{"pattern":"weekly report","before":"2j","items":["Report progres"],"line":1}]' ]
  [ "$stderr" = $'prep: baris 2 dilewati\nprep: baris 3 dilewati\nprep: baris 4 dilewati' ]
}

@test "lines with no items, only separators, or a bad before are skipped" {
  prep_write 'a | 10m | ;;' 'b | 2 jam | satu' 'c | 0x | satu' 'd | 30m | satu'
  run --separate-stderr prep_templates
  [ "$status" -eq 0 ]
  [ "$output" = '[{"pattern":"d","before":"30m","items":["satu"],"line":4}]' ]
  [ "$stderr" = $'prep: baris 1 dilewati\nprep: baris 2 dilewati\nprep: baris 3 dilewati' ]
}

# --- prep_match -------------------------------------------------------------

@test "match is a case-insensitive substring of the title" {
  prep_write 'Weekly Report | 2j | Report progres; Plan minggu depan'
  run prep_match 'Weekly Report — Tim A'
  [ "$status" -eq 0 ]
  [ "$output" = '{"pattern":"weekly report","before":"2j","items":["Report progres","Plan minggu depan"],"line":1}' ]
  run prep_match 'weekly report'
  [ "$status" -eq 0 ]
  [ "$output" = '{"pattern":"weekly report","before":"2j","items":["Report progres","Plan minggu depan"],"line":1}' ]
}

@test "match fails for a title containing no pattern" {
  prep_write 'Weekly Report | 2j | Report progres'
  run prep_match 'Standup'
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "the first of two matching lines wins" {
  prep_write 'Weekly | 2j | Pertama' 'Weekly Report | 30m | Kedua'
  run prep_match 'Weekly Report — Tim A'
  [ "$status" -eq 0 ]
  [ "$output" = '{"pattern":"weekly","before":"2j","items":["Pertama"],"line":1}' ]
}

@test "match without a file or templates fails" {
  prep_write
  run prep_match 'Weekly Report — Tim A'
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

# --- prep_due ---------------------------------------------------------------

@test "due subtracts minutes and hours, and an empty spec uses the default" {
  [ "$(prep_due "$START" '30m')" = "$(at '2026-10-22 09:30')" ]
  [ "$(prep_due "$START" '2j')" = "$(at '2026-10-22 08:00')" ]
  [ "$(prep_due "$START" '')" = "$(at '2026-10-22 08:00')" ]
}

@test "the default before follows ISLAND_PREP_BEFORE" {
  export ISLAND_PREP_BEFORE=1j
  [ "$(prep_due "$START" '')" = "$(at '2026-10-22 09:00')" ]
}

@test "due with Nh is at the deadline time N days before the start day" {
  [ "$(prep_due "$START" '1h')" = "$(at '2026-10-21 17:00')" ]
  [ "$(prep_due "$START" '2h')" = "$(at '2026-10-20 17:00')" ]
}

@test "the day-before time follows ISLAND_DEADLINE_TIME" {
  export ISLAND_DEADLINE_TIME=09:30
  [ "$(prep_due "$START" '1h')" = "$(at '2026-10-21 09:30')" ]
}

# --- prep_save --------------------------------------------------------------

@test "save into a missing file creates the folder and the file" {
  export ISLAND_PREP="$BATS_TEST_TMPDIR/baru/prep"
  run prep_save 'Weekly Report — Tim A' 'a; b'
  [ "$status" -eq 0 ]
  [ -f "$ISLAND_PREP" ]
  [ "$(cat "$ISLAND_PREP")" = 'Weekly Report — Tim A |  | a; b' ]
}

@test "save trims and drops empty items and keeps other lines and comments" {
  prep_write '# header' 'Standup | 30m | Cek blokir'
  run prep_save 'Weekly Report — Tim A' ' a ;; b ; '
  [ "$status" -eq 0 ]
  [ "$(cat "$ISLAND_PREP")" = $'# header\nStandup | 30m | Cek blokir\nWeekly Report — Tim A |  | a; b' ]
}

@test "save rewrites the first line matching the title, keeping its pola and sebelum" {
  prep_write '# header' 'Weekly | 1h | lama' 'Weekly Report | 30m | lain' 'Standup | 30m | Cek blokir'
  run prep_save 'Weekly Report — Tim A' 'baru; lagi'
  [ "$status" -eq 0 ]
  [ "$(cat "$ISLAND_PREP")" = $'# header\nWeekly | 1h | baru; lagi\nWeekly Report | 30m | lain\nStandup | 30m | Cek blokir' ]
}

@test "an empty answer removes the matching line and keeps the rest" {
  prep_write '# header' 'Weekly | 1h | lama' 'Standup | 30m | Cek blokir'
  run prep_save 'Weekly Report — Tim A' ''
  [ "$status" -eq 0 ]
  [ "$(cat "$ISLAND_PREP")" = $'# header\nStandup | 30m | Cek blokir' ]
}

@test "an empty answer without a matching line changes nothing" {
  prep_write 'Standup | 30m | Cek blokir'
  run prep_save 'Weekly Report — Tim A' '  ; ; '
  [ "$status" -eq 0 ]
  [ "$(cat "$ISLAND_PREP")" = 'Standup | 30m | Cek blokir' ]
  prep_write
  run prep_save 'Weekly Report — Tim A' ''
  [ "$status" -eq 0 ]
  [ ! -e "$ISLAND_PREP" ]
}

@test "a pipe in the title becomes a space on the appended line" {
  prep_write 'Standup | 30m | Cek blokir'
  run prep_save 'Retro | Sesi A' 'siapkan catatan'
  [ "$status" -eq 0 ]
  [ "$(cat "$ISLAND_PREP")" = $'Standup | 30m | Cek blokir\nRetro   Sesi A |  | siapkan catatan' ]
  run prep_templates
  [ "$status" -eq 0 ]
  [ "$(jq -c '.[1]' <<< "$output")" = '{"pattern":"retro   sesi a","before":"","items":["siapkan catatan"],"line":2}' ]
}

@test "a template with an empty before matches and keeps before empty" {
  prep_write 'Weekly | | a'
  run prep_templates
  [ "$status" -eq 0 ]
  [ "$output" = '[{"pattern":"weekly","before":"","items":["a"],"line":1}]' ]
  run prep_match 'Weekly Report'
  [ "$status" -eq 0 ]
  [ "$output" = '{"pattern":"weekly","before":"","items":["a"],"line":1}' ]
}

@test "lowercasing is ASCII-only for patterns and titles" {
  prep_write 'ÉQUIPE | | a'
  run prep_templates
  [ "$status" -eq 0 ]
  [ "$(jq -r '.[0].pattern' <<< "$output")" = 'Équipe' ]
  run prep_match 'équipe rapat'
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  prep_write 'équipe | | a'
  run prep_match 'équipe rapat'
  [ "$status" -eq 0 ]
  [ "$output" = '{"pattern":"équipe","before":"","items":["a"],"line":1}' ]
  run prep_match 'ÉQUIPE rapat'
  [ "$status" -eq 1 ]
}

@test "a tab inside the pattern parses and matches" {
  printf 'Weekly\tReport | 2j | a\n' > "$ISLAND_PREP"
  run prep_templates
  [ "$status" -eq 0 ]
  [ "$output" = '[{"pattern":"weekly\treport","before":"2j","items":["a"],"line":1}]' ]
  run prep_match "$(printf 'Weekly\tReport — Tim A')"
  [ "$status" -eq 0 ]
  [ "$output" = '{"pattern":"weekly\treport","before":"2j","items":["a"],"line":1}' ]
}

@test "save fails on an unreadable existing file and leaves it unchanged" {
  [ "$(id -u)" -ne 0 ] || skip 'running as root'
  prep_write 'Weekly | 1h | lama'
  chmod 000 "$ISLAND_PREP"
  run --separate-stderr prep_save 'Weekly Report' 'baru'
  [ "$status" -ne 0 ]
  [ "$stderr" = 'prep: berkas template tidak bisa dibaca' ]
  chmod 644 "$ISLAND_PREP"
  [ "$(cat "$ISLAND_PREP")" = 'Weekly | 1h | lama' ]
}
