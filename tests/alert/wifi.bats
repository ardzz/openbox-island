# tests/alert/wifi.bats
load helpers

@test "wifi only handles wifi devices and deduplicates state while preserving connection text" {
  make_fakes
  wifi_snapshot > "$RESULT"
  before=$(cat "$ALERT_FIXTURE/wifi-queries")
  {
    wifi_event 'docker0: connected'
    wifi_event 'veth123: disconnected'
    wifi_event 'tun0: connected'
    wifi_event 'p2p-dev-wlan0: connected'
    wifi_event "Connectivity is now 'full'"
    wifi_event 'NetworkManager is running'
  } >> "$RESULT"
  [ ! -s "$RESULT" ]
  [ "$(cat "$ALERT_FIXTURE/wifi-queries")" = "$before" ]
  {
    wifi_event 'wlan0: connected'
    wifi_event 'wlan0: connected'
    wifi_event "wlan0: using connection 'Home'"
    wifi_event 'wlan0: disconnected'
    wifi_event 'wlan0: disconnected'
  } >> "$RESULT"
  [ "$(jq -sc 'map([.kind,.text,.level])' "$RESULT")" = '[["wifi","Wi-Fi tersambung",-1],["wifi","Wi-Fi terputus",-1]]' ]
  [ "$(jq -sr '.[0].value' "$RESULT")" = 'Rumah "A" \ jaringan' ]
  [ "$(jq -sr '.[1].value' "$RESULT")" = '' ]
  [ "$(jq -sr 'map(.icon)|join("|")' "$RESULT")" = $'\U000F0928|\U000F092D' ]
}
