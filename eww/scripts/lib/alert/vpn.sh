#!/usr/bin/env bash
# Alert source: generic VPN interfaces, Tailscale state and exit node. Source it; do not execute.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=vpn_scan.sh
source "${BASH_SOURCE[0]%/*}/vpn_scan.sh"

ICON_VPN=$'\U000F099D'
ICON_VPN_OFF=$'\U000F099E'
ICON_TAILSCALE=$'\U000F15FC'
ICON_TAILSCALE_OFF=$'\U000F0319'
ICON_TAILSCALE_LOGIN=$'\U000F0ECC'
ICON_EXIT_NODE=$'\U000F1087'

vpn_interval() { printf '%s' "${ISLAND_VPN_INTERVAL:-10}"; }

# ts_class VAR STATE: store up, login or down in VAR.
ts_class() {
  case $2 in
    Running) printf -v "$1" up ;;
    NeedsLogin|NeedsMachineAuth) printf -v "$1" login ;;
    *) printf -v "$1" down ;;
  esac
}

# vpn_snapshot: alert per generic VPN interface change, Tailscale state change and exit node change.
vpn_snapshot() {
  local -a before=("${vpn_ifaces[@]}")
  local -A was=() now=()
  local name old_class new_class old_exit=$ts_exit_id
  ts_class old_class "$ts_state"
  vpn_scan
  ts_sample
  if [[ -z ${vpn_seen:-} ]]; then vpn_seen=1; return 0; fi
  for name in "${before[@]}"; do was[$name]=1; done
  for name in "${vpn_ifaces[@]}"; do
    now[$name]=1
    [[ -n ${was[$name]:-} ]] || alert_json vpn "$ICON_VPN" 'VPN tersambung' "$name" -1
  done
  for name in "${before[@]}"; do
    [[ -n ${now[$name]:-} ]] || alert_json vpn "$ICON_VPN_OFF" 'VPN terputus' "$name" -1
  done
  ts_class new_class "$ts_state"
  if [[ $new_class != "$old_class" ]]; then
    case $new_class in
      up) alert_json vpn "$ICON_TAILSCALE" 'Tailscale tersambung' "$ts_host" -1 ;;
      login) alert_json vpn-error "$ICON_TAILSCALE_LOGIN" 'Tailscale perlu login' '' -1 ;;
      *) if [[ $old_class == up ]]; then alert_json vpn "$ICON_TAILSCALE_OFF" 'Tailscale terputus' '' -1; fi ;;
    esac
  fi
  if [[ $ts_exit_id != "$old_exit" ]]; then
    if [[ -n $ts_exit_id ]]; then
      alert_json vpn "$ICON_EXIT_NODE" 'Exit node aktif' "$ts_exit_name" -1
    elif [[ $new_class == up ]]; then
      alert_json vpn "$ICON_EXIT_NODE" 'Exit node dimatikan' '' -1
    fi
  fi
}
