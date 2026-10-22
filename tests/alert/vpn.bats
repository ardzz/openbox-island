# tests/alert/vpn.bats
load helpers

ts_lookups() {
  grep -cx 'status --json' "$ALERT_FIXTURE/ts-calls" || :
}

@test "vpn first sample is a silent baseline" {
  make_tailscale
  make_iface tekna0 tun
  ts_peers exit-jkt
  ts_set Running n1 100.64.0.1
  {
    vpn_snapshot
    vpn_snapshot
  } > "$RESULT"
  [ ! -s "$RESULT" ]
}

@test "generic vpn interfaces alert once per interface on connect and disconnect" {
  make_tailscale
  vpn_snapshot > "$RESULT"
  make_iface tekna0 tun
  make_iface wg0 wireguard
  {
    vpn_snapshot
    vpn_snapshot
    rm -r "$ISLAND_SYSNET/tekna0"
    vpn_snapshot
  } >> "$RESULT"
  [ "$(jq -sc 'map([.kind,.text,.value,.level,.image])' "$RESULT")" = '[["vpn","VPN tersambung","tekna0",-1,""],["vpn","VPN tersambung","wg0",-1,""],["vpn","VPN terputus","tekna0",-1,""]]' ]
  [ "$(jq -sr 'map(.icon)|join("|")' "$RESULT")" = $'\U000F099D|\U000F099D|\U000F099E' ]
}

@test "tailscale, tap, plain and down interfaces are not generic vpns while ppp is" {
  make_tailscale
  make_iface tailscale0 tun
  make_iface vnet0 tap
  make_iface enp7s0 plain up
  make_iface tun1 tun down
  vpn_snapshot > "$RESULT"
  make_iface ppp0 plain
  printf 'unknown\n' > "$ISLAND_SYSNET/tun1/operstate"
  printf 'down\n' > "$ISLAND_SYSNET/tailscale0/operstate"
  vpn_snapshot >> "$RESULT"
  printf 'down\n' > "$ISLAND_SYSNET/ppp0/operstate"
  vpn_snapshot >> "$RESULT"
  [ "$(jq -sc 'map([.text,.value])' "$RESULT")" = '[["VPN tersambung","ppp0"],["VPN tersambung","tun1"],["VPN terputus","ppp0"]]' ]
}

@test "tailscale connect disconnect and login transitions" {
  make_tailscale
  vpn_snapshot > "$RESULT"
  {
    ts_set Running; vpn_snapshot
    vpn_snapshot
    ts_set Stopped; vpn_snapshot
    ts_set NeedsLogin; vpn_snapshot
    ts_set NeedsMachineAuth; vpn_snapshot
    ts_set Running; vpn_snapshot
    ts_set Starting; vpn_snapshot
    ts_set NoState; vpn_snapshot
  } >> "$RESULT"
  [ "$(jq -sc 'map([.kind,.text,.value,.level,.image])' "$RESULT")" = '[["vpn","Tailscale tersambung","loq-irx10",-1,""],["vpn","Tailscale terputus","",-1,""],["vpn-error","Tailscale perlu login","",-1,""],["vpn","Tailscale tersambung","loq-irx10",-1,""],["vpn","Tailscale terputus","",-1,""]]' ]
  [ "$(jq -sr 'map(.icon)|join("|")' "$RESULT")" = $'\U000F15FC|\U000F0319|\U000F0ECC|\U000F15FC|\U000F0319' ]
}

@test "exit node set change and clear look the name up only when the node changes" {
  make_tailscale
  ts_set Running
  vpn_snapshot > "$RESULT"
  [ "$(ts_lookups)" -eq 0 ]
  {
    ts_peers exit-jkt; ts_set Running n1 100.64.0.1; vpn_snapshot
    vpn_snapshot
    vpn_snapshot
  } >> "$RESULT"
  [ "$(ts_lookups)" -eq 1 ]
  {
    ts_peers exit-sg; ts_set Running n2 100.64.0.2; vpn_snapshot
    ts_set Running; vpn_snapshot
    ts_peers; ts_set Running n3 100.64.0.3; vpn_snapshot
    vpn_snapshot
  } >> "$RESULT"
  [ "$(ts_lookups)" -eq 3 ]
  [ "$(jq -sc 'map([.kind,.text,.value,.level])' "$RESULT")" = '[["vpn","Exit node aktif","exit-jkt",-1],["vpn","Exit node aktif","exit-sg",-1],["vpn","Exit node dimatikan","",-1],["vpn","Exit node aktif","100.64.0.3",-1]]' ]
  [ "$(jq -sr 'map(.icon)|unique|join("|")' "$RESULT")" = $'\U000F1087' ]
}

@test "stopping tailscale with an exit node reports only the disconnect and reconnecting reports both" {
  make_tailscale
  ts_peers exit-jkt
  ts_set Running n1 100.64.0.1
  vpn_snapshot > "$RESULT"
  {
    ts_set Stopped; vpn_snapshot
    ts_set Running n1 100.64.0.1; vpn_snapshot
  } >> "$RESULT"
  [ "$(jq -sc 'map([.text,.value])' "$RESULT")" = '[["Tailscale terputus",""],["Tailscale tersambung","loq-irx10"],["Exit node aktif","exit-jkt"]]' ]
}

@test "a failing tailscale daemon or missing CLI counts as not running without stderr noise" {
  make_tailscale
  touch "$ALERT_FIXTURE/ts-down"
  {
    vpn_snapshot
    vpn_snapshot
  } > "$RESULT" 2> "$ALERT_FIXTURE/vpn-stderr"
  [ ! -s "$RESULT" ]
  rm "$ALERT_FIXTURE/ts-down"
  ts_set Running
  vpn_snapshot > "$RESULT" 2>> "$ALERT_FIXTURE/vpn-stderr"
  touch "$ALERT_FIXTURE/ts-down"
  vpn_snapshot >> "$RESULT" 2>> "$ALERT_FIXTURE/vpn-stderr"
  [ "$(jq -sc 'map(.text)' "$RESULT")" = '["Tailscale tersambung","Tailscale terputus"]' ]
  rm "$BIN/tailscale"
  ln -s "$(command -v jq)" "$BIN/jq"
  make_iface tekna0 tun
  PATH="$BIN" vpn_snapshot > "$RESULT" 2>> "$ALERT_FIXTURE/vpn-stderr"
  [ "$(jq -sc 'map([.text,.value])' "$RESULT")" = '[["VPN tersambung","tekna0"]]' ]
  [ ! -s "$ALERT_FIXTURE/vpn-stderr" ]
}
