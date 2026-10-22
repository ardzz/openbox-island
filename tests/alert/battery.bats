# tests/alert/battery.bats
load helpers

@test "battery transitions emit once each and plugging in uses the charging kind" {
  {
    battery_update discharging 76
    battery_update charging 76
    battery_update charging 77
    battery_update discharging 77
    battery_update pending-charge 78
    battery_update discharging 78
    battery_update fully-charged 100
    battery_update fully-charged 100
    battery_update discharging 100
  } > "$RESULT"
  [ "$(jq -sc 'map([.kind,.text,.value,.level])' "$RESULT")" = '[["charging","Mengisi daya","76%",76],["battery","Charger dicabut","77%",77],["battery","Charger dicabut","78%",78],["battery","Baterai penuh","100%",100],["battery","Charger dicabut","100%",100]]' ]
  [ "$(jq -sr 'map(.icon)|join("|")' "$RESULT")" = $'\U000F0084|\U000F0079|\U000F0079|\U000F0079|\U000F0079' ]
  [ "$(jq -sc 'map(.image)|unique' "$RESULT")" = '[""]' ]
}

@test "low and critical battery crossings do not repeat below their thresholds" {
  {
    battery_update discharging 21
    battery_update discharging 20
    battery_update discharging 20
    battery_update discharging 19
    battery_update discharging 11
    battery_update discharging 10
    battery_update discharging 9
  } > "$RESULT"
  [ "$(jq -sc 'map([.kind,.text,.value,.level])' "$RESULT")" = '[["battery-low","Baterai lemah","20%",20],["battery-low","Baterai kritis","10%",10]]' ]
  [ "$(jq -sr 'map(.icon)|join("|")' "$RESULT")" = $'\U000F12A1|\U000F12A1' ]
}

@test "starting with a low battery or crossing thresholds while charging is silent" {
  {
    battery_update discharging 9
    battery_update discharging 8
    battery_update charging 21
    battery_update charging 20
    battery_update charging 10
  } > "$RESULT"
  [ "$(jq -sc 'map(.text)' "$RESULT")" = '["Mengisi daya"]' ]
}

@test "fractional battery snapshots truncate percentages and retain charging transitions" {
  make_fakes
  battery_path=/org/freedesktop/UPower/devices/battery_BAT1
  {
    printf '21.9\n' > "$ALERT_FIXTURE/battery-percent"
    battery_snapshot
    printf '19.5\n' > "$ALERT_FIXTURE/battery-percent"
    battery_snapshot
    printf 'charging\n' > "$ALERT_FIXTURE/battery-state"
    battery_snapshot
    printf 'discharging\n' > "$ALERT_FIXTURE/battery-state"
    printf '09.9\n' > "$ALERT_FIXTURE/battery-percent"
    battery_snapshot
  } > "$RESULT"
  [ "$battery_value" -eq 9 ]
  [ "$battery_state" = discharging ]
  [ "$(jq -sc 'map([.kind,.text,.value,.level])' "$RESULT")" = '[["battery-low","Baterai lemah","19%",19],["charging","Mengisi daya","19%",19],["battery","Charger dicabut","9%",9],["battery-low","Baterai kritis","9%",9]]' ]
}
