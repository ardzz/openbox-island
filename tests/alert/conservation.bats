# tests/alert/conservation.bats
load helpers

@test "conservation mode toggles emit battery alerts after a silent baseline" {
  printf '1\n' > "$ISLAND_CONSERVATION"
  conservation_find
  [ "$conservation_file" = "$ISLAND_CONSERVATION" ]
  {
    conservation_snapshot
    conservation_snapshot
    printf '0\n' > "$ISLAND_CONSERVATION"; conservation_snapshot
    conservation_snapshot
    printf '1\n' > "$ISLAND_CONSERVATION"; conservation_snapshot
  } > "$RESULT"
  [ "$(jq -sc 'map([.kind,.text,.value,.level,.image])' "$RESULT")" = '[["battery","Pengisian penuh","100%",-1,""],["battery","Batas pengisian aktif","80%",-1,""]]' ]
  [ "$(jq -sr 'map(.icon)|join("|")' "$RESULT")" = $'\U000F0079|\U000F0081' ]
}

@test "charging alert notes the 80% limit while conservation mode is on" {
  printf '1\n' > "$ISLAND_CONSERVATION"
  conservation_find
  {
    battery_update discharging 76
    battery_update charging 76
    printf '0\n' > "$ISLAND_CONSERVATION"
    battery_update discharging 76
    battery_update charging 76
  } > "$RESULT"
  [ "$(jq -sc 'map(select(.kind == "charging") | [.text,.value,.level])' "$RESULT")" = '[["Mengisi daya","76% · batas 80%",76],["Mengisi daya","76%",76]]' ]
}

@test "a missing conservation override is not replaced by sysfs and leaves charging unchanged" {
  local rc=0
  conservation_find || rc=$?
  [ "$rc" -ne 0 ]
  [ -z "${conservation_file:-}" ]
  {
    battery_update discharging 76
    battery_update charging 76
  } > "$RESULT"
  [ "$(jq -sc 'map([.kind,.value])' "$RESULT")" = '[["charging","76%"]]' ]
}
