#!/usr/bin/env bash
# A window of ROWS items over a JSON list. Source it after core.sh; do not execute.

# shellcheck disable=SC2016 # jq variables
PAGED_JQ='length as $n | ([([$offset, $n - $rows] | min), 0] | max) as $o | .[$o:$o + $rows] as $page
  | {rows: $page, more: ($n - $o - ($page | length)), offset: $o}'

# paged ITEMS_JSON OFFSET ROWS: {rows, more, offset} with OFFSET clamped to [0, max(0, n - ROWS)];
# more counts the items after the window.
paged() {
  jq -c --argjson offset "$2" --argjson rows "$3" "$PAGED_JQ" <<< "$1"
}
