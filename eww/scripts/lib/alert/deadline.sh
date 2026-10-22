#!/usr/bin/env bash
# Alert source: to-do deadline reminders, sent as notifications so they stay in the history.
# Source it; do not execute.
# shellcheck source=../store.sh
source "$DIR/lib/store.sh"
# shellcheck source=../todo/data.sh
source "$DIR/lib/todo/data.sh"
# shellcheck source=../todo/deadline.sh
source "$DIR/lib/todo/deadline.sh"

# Add $keys to item $id's fired reminders while it is open with deadline $due; null otherwise.
DEADLINE_MARK_JQ='if any(.items[]; .id == $id and .due == $due and (.done | not))
  then .items |= map(if .id == $id then .reminded = ((.reminded // []) + $keys | unique) else . end)
  else null end'

deadline_init() { alert_need notify-send; }
deadline_interval() { printf '%s' "${ISLAND_DEADLINE_INTERVAL:-30}"; }

# deadline_snapshot: for each open item before its deadline, mark the reminders now due, then
# notify once for them. Marking first keeps a reminder from firing twice.
deadline_snapshot() {
  local now doc id due text keys
  now=$(todo_now)
  doc=$(store_read "$TODO_FILE" "$TODO_EMPTY")
  while IFS=$'\t' read -r id due text; do
    keys=$(jq -c --argjson id "$id" --argjson k "$(deadline_passed_keys "$due" "$now")" \
      '.items[] | select(.id == $id) | $k - (.reminded // [])' <<< "$doc")
    [[ $keys != '[]' ]] || continue
    store_update "$TODO_FILE" "$TODO_EMPTY" "$TODO_NORMALIZE_JQ | ($DEADLINE_MARK_JQ)" \
      --argjson id "$id" --argjson due "$due" --argjson keys "$keys" || continue
    notify-send -a Tugas -- "$(deadline_title "$due" "$now")" "$text" || :
  done < <(jq -r --argjson now "$now" \
    '.items[] | select((.done | not) and .due != null and .due > $now) | [.id, .due, .text] | @tsv' <<< "$doc")
}
