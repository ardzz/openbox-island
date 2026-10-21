#!/usr/bin/env bash
# Shared helpers for island scripts. Source it; do not execute.
export LC_ALL=C.UTF-8

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
