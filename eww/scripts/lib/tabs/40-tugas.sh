#!/usr/bin/env bash
# Tugas: offered while its listener runs, or while the stored list has an open item.
# shellcheck source=../todo/data.sh
source "$(dirname "${BASH_SOURCE[0]}")/../todo/data.sh"
tab_tugas_available() { [[ -p $ISLAND_STATE/todo.fifo ]] || jq -e 'any(.items[]?; .done == false)' "$TODO_FILE" > /dev/null 2>&1; }
