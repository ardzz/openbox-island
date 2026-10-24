#!/usr/bin/env bash
# The to-do list file, shared by scripts/todo and the deadline alert source.
# Source it after core.sh and store.sh; do not execute.
TODO_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/eww-island/todo.json"
TODO_EMPTY='{"next_id":1,"items":[]}'
# shellcheck disable=SC2034 # read by scripts/todo and lib/prep/sync.sh
MAX_TEXT=200

# Raw text -> one trimmed line of at most $max characters ($t is the raw text).
# shellcheck disable=SC2034 # read by scripts/todo and lib/prep/sync.sh
TEXT_JQ='$t | gsub("[[:cntrl:][:space:]]+"; " ") | ltrimstr(" ") | .[:$max] | rtrimstr(" ")'

# A stored list failing this is corrupt: it reads as empty and is kept aside on the next change.
# shellcheck disable=SC2034 # read by lib/store.sh
STORE_VALID_JQ='type == "object" and (.items | type) == "array"
  and all(.items[]; type == "object" and (.id | type) == "number" and (.text | type) == "string"
    and (.done | type) == "boolean" and (.due == null or (.due | type) == "number")
    and (.reminded == null or (.reminded | type) == "array"))'
# A stored list -> the list with next_id past every id.
TODO_NORMALIZE_JQ='{next_id: ([(.next_id | numbers) // 0, ((.items | map(.id) | max) // 0) + 1] | max), items}'

# todo_now: the current epoch second; ISLAND_NOW pins it for tests.
todo_now() { printf '%s' "${ISLAND_NOW:-$EPOCHSECONDS}"; }

# todo_change FILTER [JQ ARGS...]: apply FILTER to the list and tell the listener.
# Status 1 when FILTER answers null (nothing saved), 3 on other failures.
todo_change() {
  local rc=0
  store_update "$TODO_FILE" "$TODO_EMPTY" "$TODO_NORMALIZE_JQ | ($1)" "${@:2}" || rc=$?
  if (( rc == 0 )); then fifo_signal todo '@refresh'; return 0; fi
  return $(( rc == 1 ? 1 : 3 ))
}

# todo_change_doc FILTER [JQ ARGS...]: like todo_change, but print the saved list.
todo_change_doc() {
  local new rc=0
  new=$(STORE_EMIT_DOC=1 store_update "$TODO_FILE" "$TODO_EMPTY" "$TODO_NORMALIZE_JQ | ($1)" "${@:2}") || rc=$?
  if (( rc == 0 )); then printf '%s' "$new"; fifo_signal todo '@refresh'; return 0; fi
  return $(( rc == 1 ? 1 : 3 ))
}
