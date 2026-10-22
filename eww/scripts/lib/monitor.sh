#!/usr/bin/env bash
# Event monitors and background workers. Source it after core.sh; do not execute.

# monitor_start: optional function run once CMD runs, before its first line. Take a snapshot there:
# a change between the snapshot and the monitor's start is then never missed.
monitor_start=${monitor_start:-}
# monitor_pid: the running monitor command, empty between runs (kill it from a worker's EXIT trap).
monitor_pid=''
worker_pids=()

# monitor_run HANDLER CMD...: run CMD and hand each output line to HANDLER until CMD exits.
# A process substitution, unlike a coproc, keeps its output readable after a quick CMD is reaped.
monitor_run() {
  local handler=$1 line fd
  shift
  exec {fd}< <(exec "$@" < /dev/null)
  monitor_pid=$!
  if [[ -n $monitor_start ]]; then "$monitor_start"; fi
  while IFS= read -r -u "$fd" line; do "$handler" "$line"; done
  exec {fd}<&-
  wait "$monitor_pid" 2>/dev/null || :
  monitor_pid=''
}

# workers_start FN...: run each FN in the background with the caller's stdout; worker_pids lists them.
workers_start() {
  local fn
  for fn in "$@"; do
    "$fn" &
    worker_pids+=("$!")
  done
}

# workers_stop: TERM every worker and wait for it.
workers_stop() {
  local pid
  for pid in "${worker_pids[@]}"; do kill "$pid" 2>/dev/null || :; done
  for pid in "${worker_pids[@]}"; do wait "$pid" 2>/dev/null || :; done
  worker_pids=()
}
