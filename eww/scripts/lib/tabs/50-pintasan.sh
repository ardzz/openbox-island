#!/usr/bin/env bash
# Pintasan: the shortcuts config has at least one valid shortcut.
tab_pintasan_available() { [[ $("$ISLAND_CFG/scripts/shortcuts" list 2>/dev/null) == '[['* ]]; }
