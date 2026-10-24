#!/usr/bin/env bash
# Deadlines as epoch seconds in the local time zone: reminder times, titles.
# Source it after core.sh; do not execute.

# deadline_at EPOCH DAYS HH:MM: HH:MM on the local day DAYS days after EPOCH's day.
deadline_at() {
  local day
  day=$(TZ=UTC0 date -d "$(date -d "@$1" +%F) $2 days" +%F) && date -d "$day $3" +%s
}

# deadline_passed_keys DUE NOW: the reminders ("eve" the day before, "day" on the day) that exist
# for DUE and are due by NOW, as a JSON array. An empty ISLAND_DEADLINE_EVE/DAY disables one.
deadline_passed_keys() {
  local key time days at keys=()
  for key in eve day; do
    if [[ $key == eve ]]; then time=${ISLAND_DEADLINE_EVE-09:00} days=-1
    else time=${ISLAND_DEADLINE_DAY-09:00} days=0; fi
    [[ -n $time ]] || continue
    at=$(deadline_at "$1" "$days" "$time") || continue
    if (( at < $1 && at <= $2 )); then keys+=("\"$key\""); fi
  done
  local IFS=,
  printf '[%s]\n' "${keys[*]}"
}

# deadline_title DUE NOW: the reminder title, today or tomorrow as seen from NOW.
deadline_title() {
  local when
  when=$(date -d "@$1" +%H:%M)
  if [[ $(date -d "@$1" +%F) == "$(date -d "@$2" +%F)" ]]; then
    printf 'Deadline hari ini · %s\n' "$when"
  else
    printf 'Deadline besok · %s\n' "$when"
  fi
}
