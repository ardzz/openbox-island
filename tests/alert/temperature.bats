# tests/alert/temperature.bats
load helpers

set_temp() {
  printf '%s\n' "$2" > "$ISLAND_HWMON/$1_input"
}

@test "temperature warns once per crossing and re-arms only below threshold minus five" {
  make_hwmon hwmon0 'CPU Temperature:50000' 'GPU Temperature:50000'
  temperature_find
  {
    temperature_snapshot
    set_temp hwmon0/temp1 94999; temperature_snapshot
    set_temp hwmon0/temp1 95000; temperature_snapshot
    set_temp hwmon0/temp1 99000; temperature_snapshot
    set_temp hwmon0/temp1 90500; temperature_snapshot
    set_temp hwmon0/temp1 96000; temperature_snapshot
    set_temp hwmon0/temp1 89999; temperature_snapshot
    set_temp hwmon0/temp1 96400; temperature_snapshot
    set_temp hwmon0/temp2 86999; temperature_snapshot
    set_temp hwmon0/temp2 87000; temperature_snapshot
    temperature_snapshot
  } > "$RESULT"
  [ "$(jq -sc 'map([.kind,.text,.value,.level,.image])' "$RESULT")" = '[["temperature","CPU panas","95°C",-1,""],["temperature","CPU panas","96°C",-1,""],["temperature","GPU panas","87°C",-1,""]]' ]
  [ "$(jq -sr 'map(.icon)|join("|")' "$RESULT")" = $'\U000F050F|\U000F050F|\U000F050F' ]
}

@test "starting hot is silent until re-armed and thresholds follow the environment" {
  export ISLAND_TEMP_CPU=80 ISLAND_TEMP_GPU=70
  make_hwmon hwmon0 'CPU Temperature:85000' 'GPU Temperature:72000'
  temperature_find
  {
    temperature_snapshot
    temperature_snapshot
    set_temp hwmon0/temp1 75500; temperature_snapshot
    set_temp hwmon0/temp1 81000; temperature_snapshot
    set_temp hwmon0/temp1 74000; temperature_snapshot
    set_temp hwmon0/temp1 80000; temperature_snapshot
    set_temp hwmon0/temp2 64000; temperature_snapshot
    set_temp hwmon0/temp2 70000; temperature_snapshot
  } > "$RESULT"
  [ "$(jq -sc 'map([.text,.value])' "$RESULT")" = '[["CPU panas","80°C"],["GPU panas","70°C"]]' ]
}

@test "cpu sensor prefers CPU Temperature then Package id 0 then Tctl" {
  make_hwmon hwmon0 'Composite:40000'
  make_hwmon hwmon1 'Tctl:40000'
  make_hwmon hwmon2 'Package id 0:40000' 'Core 0:40000'
  make_hwmon hwmon3 'CPU Temperature:40000' 'GPU Temperature:40000'
  {
    (
      temperature_find; temperature_snapshot
      set_temp hwmon0/temp1 99000; set_temp hwmon1/temp1 99000
      set_temp hwmon2/temp1 99000; set_temp hwmon2/temp2 99000
      temperature_snapshot
      set_temp hwmon3/temp1 97000; temperature_snapshot
    )
    rm -r "$ISLAND_HWMON/hwmon3"
    set_temp hwmon1/temp1 40000; set_temp hwmon2/temp1 40000
    (
      temperature_find; temperature_snapshot
      set_temp hwmon1/temp1 99000; temperature_snapshot
      set_temp hwmon2/temp1 98000; temperature_snapshot
    )
    rm -r "$ISLAND_HWMON/hwmon2"
    set_temp hwmon1/temp1 40000
    (
      temperature_find; temperature_snapshot
      set_temp hwmon0/temp1 99000; temperature_snapshot
      set_temp hwmon1/temp1 96000; temperature_snapshot
    )
  } > "$RESULT"
  [ "$(jq -sc 'map([.text,.value])' "$RESULT")" = '[["CPU panas","97°C"],["CPU panas","98°C"],["CPU panas","96°C"]]' ]
}
