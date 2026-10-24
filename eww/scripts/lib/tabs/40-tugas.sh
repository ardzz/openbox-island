#!/usr/bin/env bash
# Tugas: offered while its listener runs, while the stored list has an open item, or
# while a deadline-picker request is pending (its item may already be done).
# shellcheck source=../todo/data.sh
source "$(dirname "${BASH_SOURCE[0]}")/../todo/data.sh"
tab_tugas_available() { [[ -p $ISLAND_STATE/todo.fifo || -e $ISLAND_STATE/todo-pick ]] || jq -e 'any(.items[]?; .done == false)' "$TODO_FILE" > /dev/null 2>&1; }
