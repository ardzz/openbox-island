#!/usr/bin/env bash
# The Tugas tab's JSON. Source it after paged.sh; do not execute.

# A list -> the tab against $now: open items with a deadline soonest first, other open items newest
# first, then done items latest finished first. Open rows with a deadline carry a chip label and class.
# shellcheck disable=SC2034 # read by scripts/todo
TODO_RENDER_JQ='
def day0: strflocaltime("%Y-%m-%d") | strptime("%Y-%m-%d") | mktime;
def chip:
  if .done or .due == null then {due_label: "", due_class: ""}
  elif .due <= $now then {due_label: "terlambat", due_class: "due-late"}
  else (((.due | day0) - ($now | day0)) / 86400 | floor) as $days
    | (.due | strflocaltime("%H:%M")) as $time
    | {due_label: (if $days == 0 then $time
        elif $days == 1 then "besok " + $time
        elif $days < 7 then ["Sen","Sel","Rab","Kam","Jum","Sab","Min"][(.due | strflocaltime("%u") | tonumber) - 1] + " " + $time
        else (.due | strflocaltime("%d") | tonumber | tostring) + " "
          + ["Jan","Feb","Mar","Apr","Mei","Jun","Jul","Agu","Sep","Okt","Nov","Des"][(.due | strflocaltime("%m") | tonumber) - 1]
        end),
       due_class: (if .due - $now < 86400 then "due-soon" else "" end)}
  end;
(.items | map(select((.done | not) and .due != null)) | sort_by(.due, -.id)) as $timed
| (.items | map(select((.done | not) and .due == null)) | sort_by(-.id)) as $open
| (.items | map(select(.done)) | sort_by(-(.done_at // 0), -.id)) as $done
| ($timed + $open + $done) as $all | ($timed + $open | length) as $count
| ($all | '"$PAGED_JQ"') as $page
| {open: $count, done: ($done | length), total: ($all | length),
   label: ("Tugas" + (if $count > 0 then " \($count)" else "" end)),
   rows: [$page.rows[] | {id, text, done} + chip], more: $page.more, offset: $page.offset}'
