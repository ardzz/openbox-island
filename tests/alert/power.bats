# tests/alert/power.bats
load helpers

set_profile() {
  printf '%s\n' "$1" > "$ISLAND_PLATFORM_PROFILE"
}

@test "power profile changes emit the mode name with a per-mode icon after a silent baseline" {
  set_profile performance
  {
    power_snapshot
    power_snapshot
    set_profile low-power; power_snapshot
    set_profile balanced; power_snapshot
    power_snapshot
    set_profile performance; power_snapshot
    set_profile max-power; power_snapshot
    set_profile custom; power_snapshot
    set_profile quiet; power_snapshot
  } > "$RESULT"
  [ "$(jq -sc 'map([.kind,.text,.value,.level,.image])' "$RESULT")" = '[["power","Mode daya","Hemat daya",-1,""],["power","Mode daya","Seimbang",-1,""],["power","Mode daya","Performa",-1,""],["power","Mode daya","Daya maksimum",-1,""],["power","Mode daya","Kustom",-1,""],["power","Mode daya","quiet",-1,""]]' ]
  [ "$(jq -sr 'map(.icon)|join("|")' "$RESULT")" = $'\U000F032A|\U000F05D1|\U000F04C5|\U000F0463|\U000F062E|\U000F062E' ]
}

@test "power profile snapshot fails without emitting when the file is unreadable" {
  run power_snapshot
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}
