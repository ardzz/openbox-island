#!/usr/bin/env bash
# Absolute deadlines on top of listen's idle tick. Source it after lib/listener.sh; do not execute.

# wake_at DEADLINE: call from HANDLE_FN so its next "@tick" comes at DEADLINE (EPOCHREALTIME in
# microseconds, 0 = none). listen restarts the idle clock right before HANDLE_FN, so the tick may come
# a little early: the handler checks its deadline and calls wake_at again.
wake_at() {
  local remaining
  if (( ! $1 )); then listen_tick=0; return; fi
  remaining=$(($1 - ${EPOCHREALTIME/./}))
  (( remaining > 0 )) || remaining=1
  # shellcheck disable=SC2034 # read by listen
  printf -v listen_tick '%d.%06d' "$((remaining / 1000000))" "$((remaining % 1000000))"
}
