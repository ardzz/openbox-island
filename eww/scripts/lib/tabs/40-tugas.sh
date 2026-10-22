#!/usr/bin/env bash
# Tugas: offered even when empty (the first item is added from it) while its listener runs.
tab_tugas_available() { [[ -p $ISLAND_STATE/todo.fifo ]]; }
