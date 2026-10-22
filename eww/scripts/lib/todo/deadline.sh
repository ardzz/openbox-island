#!/usr/bin/env bash
# Deadlines as epoch seconds in the local time zone: Indonesian phrases, reminder times, titles.
# Source it after core.sh; do not execute.

# shellcheck disable=SC2034 # read by scripts/todo
DEADLINE_PRESETS=('Hari ini 17:00' 'Besok 09:00' 'Besok 17:00' 'Jumat 17:00' 'Senin 09:00')
DEADLINE_DAYS=(senin selasa rabu kamis jumat sabtu minggu)
DEADLINE_MONTHS=(jan feb mar apr mei jun jul agu sep okt nov des)

# deadline_at EPOCH DAYS HH:MM: HH:MM on the local day DAYS days after EPOCH's day.
deadline_at() {
  local day
  day=$(date -d "$(date -d "@$1" +%F) $2 days" +%F) && date -d "$day $3" +%s
}

# deadline_date TEXT NOW: "D MONTH" or "D/M" as YYYY-MM-DD in NOW's year.
deadline_date() {
  local d='' mon='' i
  if [[ $1 =~ ^([0-9]{1,2})\ ([a-z]{3})[a-z]*$ ]]; then
    d=$((10#${BASH_REMATCH[1]}))
    for i in "${!DEADLINE_MONTHS[@]}"; do
      if [[ ${BASH_REMATCH[2]} == "${DEADLINE_MONTHS[i]}" ]]; then mon=$((i + 1)); fi
    done
  elif [[ $1 =~ ^([0-9]{1,2})/([0-9]{1,2})$ ]]; then
    d=$((10#${BASH_REMATCH[1]})) mon=$((10#${BASH_REMATCH[2]}))
  fi
  [[ -n $mon ]] && (( mon <= 12 && d >= 1 )) || return 1
  printf '%s-%02d-%02d\n' "$(date -d "@$2" +%Y)" "$mon" "$d"
}

# deadline_parse TEXT NOW: the deadline TEXT names, after NOW; fails on anything else.
# TEXT: [hari ini|besok|lusa|WEEKDAY|D MONTH|D/M] [HH:MM|HH.MM|jam HH[:MM]], at least one part.
deadline_parse() {
  local s now=$2 h='' m=0 time offset='' roll=0 date='' target i
  s=$(tr -s '[:space:]' ' ' <<< "${1,,}"); s=${s# }; s=${s% }
  if [[ $s =~ ^(.*)(^| )jam\ ([0-9]{1,2})([:.]([0-9]{2}))?$ ]]; then
    s=${BASH_REMATCH[1]} h=$((10#${BASH_REMATCH[3]}))
    if [[ -n ${BASH_REMATCH[5]} ]]; then m=$((10#${BASH_REMATCH[5]})); fi
  elif [[ $s =~ ^(.*)(^| )([0-9]{1,2})[:.]([0-9]{2})$ ]]; then
    s=${BASH_REMATCH[1]} h=$((10#${BASH_REMATCH[3]})) m=$((10#${BASH_REMATCH[4]}))
  fi
  time=${ISLAND_DEADLINE_TIME:-17:00}
  if [[ -n $h ]]; then
    (( h <= 23 && m <= 59 )) || return 1
    printf -v time '%02d:%02d' "$h" "$m"
  fi
  case $s in
    '') [[ -n $h ]] || return 1; offset=0 roll=1 ;;
    'hari ini') offset=0 ;;
    besok) offset=1 ;;
    lusa) offset=2 ;;
    *)
      for i in "${!DEADLINE_DAYS[@]}"; do
        if [[ $s == "${DEADLINE_DAYS[i]}" ]]; then
          offset=$(( (i + 1 - $(date -d "@$now" +%u) + 7) % 7 )) roll=7
        fi
      done
      if [[ -z $offset ]]; then date=$(deadline_date "$s" "$now") || return 1; fi ;;
  esac
  if [[ -n $date ]]; then
    target=$(date -d "$date $time" +%s 2>/dev/null) || return 1
    if (( target <= now )); then
      target=$(date -d "$(( ${date%%-*} + 1 ))-${date#*-} $time" +%s 2>/dev/null) || return 1
    fi
  else
    target=$(deadline_at "$now" "$offset" "$time") || return 1
    if (( target <= now && roll )); then target=$(deadline_at "$now" "$((offset + roll))" "$time") || return 1; fi
  fi
  (( target > now )) || return 1
  printf '%s\n' "$target"
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
