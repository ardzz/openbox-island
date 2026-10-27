#!/usr/bin/env bash
tab_kuota_available() { [[ -f $ISLAND_STATE/kuota.json ]] && jq -e '.ok == true' "$ISLAND_STATE/kuota.json" > /dev/null 2>&1; }
