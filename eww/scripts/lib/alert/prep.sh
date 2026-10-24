#!/usr/bin/env bash
# Alert source: create meeting prep items ahead of matching meetings.
# Source it; do not execute.
# shellcheck source=../store.sh
source "$DIR/lib/store.sh"
# shellcheck source=../todo/data.sh
source "$DIR/lib/todo/data.sh"
# shellcheck source=../todo/deadline.sh
source "$DIR/lib/todo/deadline.sh"
# shellcheck source=../prep/template.sh
source "$DIR/lib/prep/template.sh"
# shellcheck source=../prep/sync.sh
source "$DIR/lib/prep/sync.sh"

prep_interval() { printf '%s' "${ISLAND_PREP_INTERVAL:-60}"; }
prep_snapshot() { prep_sync; }
