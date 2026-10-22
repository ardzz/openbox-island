#!/usr/bin/env bash
# VPN interface and Tailscale sampling for the vpn alert source. Source it; do not execute.
# shellcheck disable=SC2034 # results are read by vpn.sh

declare -ga vpn_ifaces=()
declare -g ts_state='' ts_host='' ts_exit_id='' ts_exit_name=''

# vpn_scan: up tun (not tap), WireGuard and ppp interfaces, excluding tailscale*. Fork-free.
vpn_scan() {
  local dir name flags line state found
  vpn_ifaces=()
  for dir in "${ISLAND_SYSNET:-/sys/class/net}"/*; do
    name=${dir##*/}
    [[ -d $dir && $name != tailscale* ]] || continue
    found=0
    if [[ $name == ppp* ]]; then
      found=1
    elif [[ -e $dir/tun_flags ]]; then
      flags=''
      IFS= read -r flags 2>/dev/null < "$dir/tun_flags" || :
      # IFF_TAP (0x2) devices are VM taps such as libvirt vnetN, not tunnels.
      if [[ $flags =~ ^0x[0-9A-Fa-f]+$ ]] && (( ! (flags & 2) )); then found=1; fi
    elif [[ -r $dir/uevent ]]; then
      while IFS= read -r line; do
        if [[ $line == DEVTYPE=wireguard ]]; then found=1; break; fi
      done < "$dir/uevent"
    fi
    (( found )) || continue
    state=''
    IFS= read -r state 2>/dev/null < "$dir/operstate" || :
    # tun devices report "unknown" while up.
    [[ $state != down ]] || continue
    vpn_ifaces+=("$name")
  done
}

# ts_sample: Tailscale backend state, own host name and exit node. A missing CLI or daemon
# leaves ts_state empty. The exit node name is looked up only when the exit node changes.
ts_sample() {
  local raw='' id='' ip=''
  ts_state='' ts_host=''
  if command -v tailscale > /dev/null 2>&1 && raw=$(tailscale status --json --peers=false 2>/dev/null); then
    raw=$(jq -r '[.BackendState // "", .Self.HostName // "", .ExitNodeStatus.ID // "",
      (.ExitNodeStatus.TailscaleIPs[0]? // "")] | map(tostring) | join("\u001f")' <<< "$raw" 2>/dev/null) || raw=''
    IFS=$'\x1f' read -r ts_state ts_host id ip <<< "$raw"
  fi
  [[ $ts_state == Running ]] || id=''
  [[ $id != "$ts_exit_id" ]] || return 0
  ts_exit_id=$id ts_exit_name=''
  [[ -n $id ]] || return 0
  ts_exit_name=$(tailscale status --json 2>/dev/null |
    jq -r 'first(.Peer[]? | select(.ExitNode == true) | .HostName) // empty' 2>/dev/null) || ts_exit_name=''
  [[ -n $ts_exit_name ]] || ts_exit_name=${ip%%/*}
}
