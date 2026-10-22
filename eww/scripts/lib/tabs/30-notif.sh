#!/usr/bin/env bash
# Notifikasi: the notification center holds at least one entry.
tab_notif_available() { [[ $(island_eww get notif_center 2>/dev/null | jq -r '(.total // 0) > 0' 2>/dev/null) == true ]]; }
