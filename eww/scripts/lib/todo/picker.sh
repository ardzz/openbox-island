#!/usr/bin/env bash
# Deadline picker state for the Tugas tab. Source it after core.sh and todo/data.sh;
# do not execute. The picker lives in the scripts/todo listener: TODO_PICKER_JQ renders it.

pick_reset() { pick_show=0 pick_id=0 pick_sel='' pick_time='' pick_month=''; }

# pick_request_file: a pending picker-open id survives the card-only listener being stopped.
pick_request_file() { printf '%s' "$ISLAND_STATE/todo-pick"; }

# pick_request_write ID: record ID atomically as the pending picker-open request.
pick_request_write() {
  local file tmp
  file=$(pick_request_file)
  mkdir -p "$ISLAND_STATE" || return 1
  tmp=$(mktemp "$ISLAND_STATE/.todo-pick.XXXXXX") || return 1
  if printf '%s\n' "$((10#$1))" > "$tmp" && mv -f -- "$tmp" "$file"; then return 0; fi
  rm -f -- "$tmp"
  return 1
}

# pick_request_clear: drop the pending picker-open request.
pick_request_clear() { rm -f -- "$(pick_request_file)"; }

# pick_request_open: on load, open the picker from the recorded request when it is not
# already open on that id; requests for a gone item are dropped.
pick_request_open() {
  local file id
  file=$(pick_request_file)
  [[ -f $file ]] || return 0
  id=$(cat "$file" 2>/dev/null)
  [[ $id =~ ^[0-9]+$ ]] || { pick_request_clear; return 0; }
  if (( pick_show )) && [[ $pick_id == "$((10#$id))" ]]; then return 0; fi
  if pick_open "$id"; then return 0; fi
  pick_close
}

# pick_add_id TEXT: add TEXT without a deadline and print the allocated id. TEXT must
# already be validated (non-empty after trimming, as in add).
pick_add_id() {
  local text new
  text=$(jq -rn --arg t "$1" --argjson max "$MAX_TEXT" "$TEXT_JQ") || return
  [[ -n $text ]] || return 1
  new=$(todo_change_doc "$ADD_JQ" --arg text "$text" --argjson now "$(now_us)" \
    --argjson due null --argjson reminded null) || return
  jq -er --arg text "$text" '[.items[] | select(.text == $text) | .id] | max' <<< "$new"
}

# pick_valid_day DATE: DATE is a real YYYY-MM-DD day; noon avoids DST-skipped midnights.
pick_valid_day() {
  [[ $1 =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
  [[ $(date -d "$1 12:00" +%F 2>/dev/null) == "$1" ]]
}

# pick_open_request ID: record ID and tell a live listener under the island lifecycle
# lock (so a closing card cannot delete the fresh request), then hold the card open.
pick_open_request() {
  local rc=0
  mkdir -p "$ISLAND_STATE" || return 1
  exec {pick_lock_fd}>"$ISLAND_STATE/lock" || return 1
  if ! flock "$pick_lock_fd"; then exec {pick_lock_fd}>&-; return 1; fi
  pick_request_write "$1" || rc=$?
  if (( rc == 0 )); then fifo_signal todo "@pick open $1"; fi
  exec {pick_lock_fd}>&-
  (( rc == 0 )) || return "$rc"
  "$DIR/island" auto 60 tugas
}

# pick_cmd ARGS...: validate one picker step and hand it to the listener; usage on bad input.
pick_cmd() {
  case ${1:-} in
    nav)
      (( $# == 2 )) && [[ $2 == -1 || $2 == 1 ]] || { usage; return; }
      fifo_signal todo "@pick nav $2" ;;
    day)
      (( $# == 2 )) && pick_valid_day "$2" || { usage; return; }
      fifo_signal todo "@pick day $2" ;;
    hour|minute)
      (( $# == 2 )) && [[ $2 == up || $2 == down ]] || { usage; return; }
      fifo_signal todo "@pick $1 $2" ;;
    time)
      if (( $# == 2 )) && [[ $2 =~ ^([0-9]{2}):([0-9]{2})$ ]] && (( 10#${BASH_REMATCH[1]} <= 23 && 10#${BASH_REMATCH[2]} <= 59 )); then
        fifo_signal todo "@pick time $2"
      else
        usage; return
      fi ;;
    save|clear|cancel)
      (( $# == 1 )) || { usage; return; }
      fifo_signal todo "@pick $1" ;;
    *) usage; return ;;
  esac
}

# pick_handle LINE: the listener applies one "@pick ..." line to the picker state.
pick_handle() {
  case $1 in
    '@pick open '*)
      load
      pick_open "${1#'@pick open '}" || pick_close ;;
    '@pick nav -1') (( pick_show )) && pick_nav -1 ;;
    '@pick nav 1') (( pick_show )) && pick_nav 1 ;;
    '@pick day '*) (( pick_show )) && pick_set_day "${1#'@pick day '}" ;;
    '@pick hour up') (( pick_show )) && pick_step_hour up ;;
    '@pick hour down') (( pick_show )) && pick_step_hour down ;;
    '@pick minute up') (( pick_show )) && pick_step_minute up ;;
    '@pick minute down') (( pick_show )) && pick_step_minute down ;;
    '@pick time '*) (( pick_show )) && pick_set_time "${1#'@pick time '}" ;;
    '@pick save') (( pick_show )) && pick_save ;;
    '@pick clear') (( pick_show )) && pick_clear ;;
    '@pick cancel') pick_close ;;
  esac
}

# pick_today: today as YYYY-MM-DD in the local time zone.
pick_today() { date -d "@$(todo_now)" +%F; }

# pick_default_time: ISLAND_DEADLINE_TIME when it is a valid HH:MM, else 17:00.
pick_default_time() {
  local t=${ISLAND_DEADLINE_TIME:-17:00}
  if [[ $t =~ ^([0-9]{2}):([0-9]{2})$ ]] && (( 10#${BASH_REMATCH[1]} <= 23 && 10#${BASH_REMATCH[2]} <= 59 )); then
    printf '%s' "$t"
  else
    printf '17:00'
  fi
}

# pick_epoch DATE HH:MM: the epoch of that local date and time.
pick_epoch() { date -d "$1 $2" +%s; }

# pick_anchor YYYY-MM: the 1st of that local month as YYYY-MM-DD.
pick_anchor() { printf '%s-01' "$1"; }

# pick_open ID: open the picker on ID from $doc: its deadline, or today at the default time
# while still ahead and tomorrow afterwards.
# $doc is the listener's list, set by load in scripts/todo.
# shellcheck disable=SC2154 # $doc is set by load in scripts/todo
pick_open() {
  local id=$((10#$1)) item due today
  item=$(jq -c --argjson id "$id" '.items[] | select(.id == $id)' <<< "$doc") || return 1
  [[ -n $item ]] || return 1
  today=$(pick_today)
  if due=$(jq -er 'select(.due != null) | .due' <<< "$item"); then
    pick_sel=$(date -d "@$due" +%F)
    pick_time=$(date -d "@$due" +%H:%M)
  else
    pick_time=$(pick_default_time)
    if (( $(pick_epoch "$today" "$pick_time") < $(todo_now) + 1 )); then
      pick_sel=$(date -d "$(date -d "@$(todo_now)" '+%Y-%m-%d 12:00') +1 day" +%F)
    else
      pick_sel=$today
    fi
  fi
  pick_id=$id
  pick_month=${pick_sel%???}
  pick_show=1
}

# pick_move_month ANCHOR STEP: ANCHOR moved by STEP months as YYYY-MM-DD.
pick_move_month() {
  local anchor=$1 step=$2 y m total ny nm
  y=$((10#${anchor%%-*})); m=$((10#${anchor:5:2}))
  total=$(( y * 12 + m - 1 + step ))
  ny=$(( total / 12 )); nm=$(( total % 12 + 1 ))
  printf '%04d-%02d-01' "$ny" "$nm"
}

# pick_nav STEP: show the next or previous month; the selection is untouched.
pick_nav() { pick_month=$(pick_move_month "$(pick_anchor "$pick_month")" "$1"); pick_month=${pick_month%???}; }

# pick_set_day DATE: select DATE and show its month; days before today are ignored.
pick_set_day() {
  local today; today=$(pick_today)
  [[ $1 < $today ]] && return 0
  pick_sel=$1
  pick_month=${1%???}
}

# pick_set_time HH:MM: keep the picked date, set the time.
pick_set_time() { pick_time=$1; }

# pick_step_minute up|down: move the time by 5 minutes, wrapping within the day.
pick_step_minute() {
  local h=$((10#${pick_time%%:*})) m=$((10#${pick_time##*:}))
  if [[ $1 == up ]]; then m=$(( m + 5 <= 55 ? m + 5 : 0 )); else m=$(( m >= 5 ? m - 5 : 55 )); fi
  printf -v pick_time '%02d:%02d' "$h" "$m"
}

# pick_step_hour up|down: move the time by 1 hour, wrapping 0-23.
pick_step_hour() {
  local h=$((10#${pick_time%%:*})) m=$((10#${pick_time##*:}))
  if [[ $1 == up ]]; then h=$(( h == 23 ? 0 : h + 1 )); else h=$(( h == 0 ? 23 : h - 1 )); fi
  printf -v pick_time '%02d:%02d' "$h" "$m"
}

# pick_save: store the picked deadline like set_due and close the picker.
pick_save() {
  local id=$pick_id sel=$pick_sel time=$pick_time
  pick_close
  set_due "$id" "$(pick_epoch "$sel" "$time")"
}

# pick_clear: clear the picked deadline and close the picker.
pick_clear() {
  local id=$pick_id
  pick_close
  set_due "$id" none
}

# pick_close: close the picker without changing the deadline.
pick_close() { pick_reset; pick_request_clear; }

# pick_sync: close the picker when its item is gone from $doc.
pick_sync() {
  (( pick_show )) || return 0
  if ! jq -e --argjson id "$pick_id" 'any(.items[]; .id == $id)' <<< "$doc" > /dev/null; then pick_close; fi
}

# The picker object for the render; a jq fragment reading $doc. Grid dates walk UTC noon
# so the local DST rule cannot skip or duplicate a day.
# shellcheck disable=SC2034,SC2016 # read by scripts/todo; jq variables
TODO_PICKER_JQ='
  | . + (if $pick_show == 0 then {picker: {show: false, id: 0, text: "", month_label: "", weeks: [], hour: "", minute: "", summary: ""}}
    else ($pickdoc) as $list | ($pick_id) as $pid | ($pick_sel) as $sel | ($pick_time) as $time
      | ($pick_month + "-01") as $anchor | ($today) as $td
      | ((($anchor + "T12:00:00Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime) as $first_noon
         | ((($first_noon | gmtime | strftime("%u") | tonumber) + 6) % 7) as $lead
         | ($first_noon - ($lead * 86400)) as $start
         | [range(42) | (($start + (. * 86400)) | gmtime | strftime("%Y-%m-%d"))]) as $dates
      | {picker: {show: true, id: $pid,
         text: (first($list.items[] | select(.id == $pid) | .text) // ""),
         month_label: (["Januari","Februari","Maret","April","Mei","Juni","Juli","Agustus","September","Oktober","November","Desember"][($pick_month | split("-")[1] | tonumber) - 1] + " " + ($pick_month | split("-")[0])),
         weeks: ([range(6) as $w | [range(7) as $d | $dates[$w * 7 + $d] as $date
           | {date: $date, day: (($date | split("-")[2] | tonumber) | tostring),
              cls: ([(if ($date | .[0:7]) != $pick_month then "other" else empty end),
                     (if $date < $td then "past" else empty end),
                     (if $date == $td then "today" else empty end),
                     (if $date == $sel then "sel" else empty end)] | join(" "))}]]),
         hour: ($time | split(":")[0]), minute: ($time | split(":")[1]),
         summary: ((["Sen","Sel","Rab","Kam","Jum","Sab","Min"][(($sel + "T12:00:00Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime | strftime("%u") | tonumber) - 1])
           + " " + (($sel | split("-")[2] | tonumber) | tostring) + " "
           + ["Jan","Feb","Mar","Apr","Mei","Jun","Jul","Agu","Sep","Okt","Nov","Des"][($sel | split("-")[1] | tonumber) - 1]
           + " · " + $time)}}
    end)'
