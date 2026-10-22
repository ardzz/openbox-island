#!/usr/bin/env bash
# Shared helpers for island scripts. Source it; do not execute.
export LC_ALL=C.UTF-8

# Runtime state (FIFOs, locks, caches between scripts) and the eww config dir this file lives in.
ISLAND_STATE="${XDG_RUNTIME_DIR:-/tmp}/eww-island"
ISLAND_CFG="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# island_eww ARGS...: eww on the island config. Keeps a lock fd 9 out of a daemon eww may auto-start.
island_eww() { command eww --config "$ISLAND_CFG" "$@" 9>&-; }

# shellcheck disable=SC2034 # read by alert and status
ICON_HEADPHONES=$'\U000F02CB' ICON_HEADPHONES_BT=$'\U000F0970'

MISSING_DEP=""

# require TOOL...: return 127 and remember the first missing tool.
require() {
  local dep
  for dep in "$@"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      MISSING_DEP=$dep
      return 127
    fi
  done
}

# run_forever FN [ARGS...]: keep an event stream alive.
# FN returning 127 = dependency missing: log once per outage, retry every OB_RETRY_MISSING s (5).
# Any other return = source ended: reconnect after OB_RETRY_RECONNECT s (1).
run_forever() {
  local rc logged=0
  while true; do
    "$@"
    rc=$?
    if (( rc == 127 )); then
      if (( ! logged )); then
        printf '%s: missing dependency %s, retrying every %ss\n' \
          "${0##*/}" "${MISSING_DEP:-?}" "${OB_RETRY_MISSING:-5}" >&2
        logged=1
      fi
      sleep "${OB_RETRY_MISSING:-5}"
    else
      logged=0
      sleep "${OB_RETRY_RECONNECT:-1}"
    fi
  done
}

# emit_dedup: copy stdin to stdout, dropping a line identical to the previous one.
emit_dedup() {
  local line last="" has_last=0
  while IFS= read -r line; do
    (( has_last )) && [[ $line == "$last" ]] && continue
    printf '%s\n' "$line"
    last=$line
    has_last=1
  done
}

# poll_sleep SECONDS: sleep without forking by timing out a read on a pipe nobody writes to.
poll_sleep() {
  if [[ -z ${sleep_fd:-} ]]; then exec {sleep_fd}<> <(:); fi
  read -r -t "$1" -u "$sleep_fd" || :
}

# seconds_us SECONDS: decimal seconds as integer microseconds.
seconds_us() {
  local whole=${1%%.*} fraction=''
  [[ $1 != *.* ]] || fraction=${1#*.}
  fraction=${fraction}000000
  printf '%s' "$((10#$whole * 1000000 + 10#${fraction:0:6}))"
}

# fifo_signal NAME LINE: hand LINE to the listener reading $ISLAND_STATE/NAME.fifo if it runs.
# A read-write open of a FIFO needs no reader, so this never blocks; short lines are atomic.
fifo_signal() {
  local fifo="$ISLAND_STATE/$1.fifo"
  [[ -p $fifo ]] || return 0
  printf '%s\n' "$2" 2>/dev/null 1<> "$fifo" || :
}
# notify_signal LINE: to the notification pill listener (scripts/notify).
notify_signal() { fifo_signal notify "$1"; }
# notif_signal LINE: to the notification center listener (scripts/notif).
notif_signal() { fifo_signal notif "$1"; }

# fmt_time SECONDS: m:ss below an hour, h:mm:ss from an hour. Decimals truncated; junk = 0.
fmt_time() {
  local s=${1%.*}
  [[ $s =~ ^[0-9]+$ ]] || s=0
  s=$(( 10#$s ))
  if (( s >= 3600 )); then
    printf '%d:%02d:%02d\n' $(( s / 3600 )) $(( s % 3600 / 60 )) $(( s % 60 ))
  else
    printf '%d:%02d\n' $(( s / 60 )) $(( s % 60 ))
  fi
}
