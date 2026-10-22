#!/usr/bin/env bash
# Cuaca: the last weather fetch succeeded.
tab_cuaca_available() { [[ $(island_eww get weather 2>/dev/null | jq -r '.ok // false' 2>/dev/null) == true ]]; }
