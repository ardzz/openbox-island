#!/usr/bin/env bash
# Generic alert source worker. Source it after core.sh and monitor.sh; do not execute.
#
# Source contract, lib/alert/NAME.sh for each NAME in ALERT_SOURCES:
#   NAME_init      optional discovery; non-zero disables the source (alert_skip notes why).
#   NAME_snapshot  sample the state, alerting on changes; the first sample is a silent baseline.
#   then either    NAME_monitor (print an event monitor command, each word NUL-terminated)
#                  and NAME_event LINE (handle one monitor line),
#   or             NAME_interval (print the poll period in seconds).

alert_source=''

# alert_skip REASON: note on stderr why the running source is disabled, and fail.
alert_skip() {
  printf 'alert: sumber %s dilewati, %s\n' "$alert_source" "$1" >&2
  return 1
}

# alert_need TOOL...: fail with a note when a tool is missing.
alert_need() { require "$@" || alert_skip "$MISSING_DEP tidak tersedia"; }

# source_baseline: silent snapshot taken once the monitor runs, so no change in between is missed.
source_baseline() { "${alert_source}_snapshot" > /dev/null; }

# source_stream CMD...: one monitor connection of alert_source.
source_stream() { monitor_start=source_baseline monitor_run "${alert_source}_event" "$@"; }

worker_exit() {
  if [[ -n $monitor_pid ]]; then kill "$monitor_pid" 2>/dev/null || :; fi
  wait 2>/dev/null || :
}

# source_worker: run alert_source until TERM, its alerts to stdout.
source_worker() {
  local interval
  local -a cmd
  # shellcheck disable=SC2034 # audio and brightness events then ask the main loop to extend their HUD
  worker_mode=1
  trap 'exit 0' TERM INT HUP
  trap worker_exit EXIT
  if declare -F "${alert_source}_init" > /dev/null; then "${alert_source}_init" || return 0; fi
  if declare -F "${alert_source}_interval" > /dev/null; then
    interval=$("${alert_source}_interval")
    while true; do
      "${alert_source}_snapshot" || :
      poll_sleep "$interval"
    done
  fi
  mapfile -d '' -t cmd < <("${alert_source}_monitor")
  run_forever source_stream "${cmd[@]}"
}
