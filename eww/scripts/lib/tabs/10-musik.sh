#!/usr/bin/env bash
# Musik: a player is playing, paused or loading its next track.
# media writes media.json before it calls island, so this never lags behind a stopped player.
tab_musik_available() { [[ $(jq -r '.state // "none"' "$ISLAND_STATE/media.json" 2>/dev/null) =~ ^(playing|paused|loading)$ ]]; }
