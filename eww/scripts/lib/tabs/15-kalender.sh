#!/usr/bin/env bash
# Kalender: offered while the meeting alert source publishes a readable agenda.
tab_kalender_available() { jq -e '.ok == true' "$ISLAND_STATE/agenda.json" > /dev/null 2>&1; }
