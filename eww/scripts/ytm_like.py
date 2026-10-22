#!/usr/bin/env python3
"""ytm_like VIDEO_ID: print LIKE, DISLIKE or INDIFFERENT for one YouTube Music video.

Reads with the ytm-player login (OB_YTM_AUTH overrides the path). Prints UNAVAILABLE (exit 3)
when ytmusicapi or the login is missing; any other failure prints nothing (exit 1).
"""

import os
from pathlib import Path
import re
import sys

STATUSES = {"LIKE", "DISLIKE", "INDIFFERENT"}
VIDEO_ID = re.compile(r"[A-Za-z0-9_-]{11}")


def auth_path():
    return Path(os.environ.get("OB_YTM_AUTH")
                or Path.home() / ".config" / "ytm-player" / "auth.json")


def like_status(api, video_id):
    playlist = api.get_watch_playlist(video_id, limit=1) or {}
    for track in playlist.get("tracks") or []:
        if track.get("videoId") == video_id:
            status = track.get("likeStatus")
            return status if status in STATUSES else None
    return None


def main(argv):
    if len(argv) != 1 or not VIDEO_ID.fullmatch(argv[0]):
        return 2
    auth = auth_path()
    try:
        if not auth.is_file():
            raise ImportError("no ytm-player login")
        from ytmusicapi import YTMusic
    except ImportError:
        print("UNAVAILABLE")
        return 3
    try:
        status = like_status(YTMusic(str(auth)), argv[0])
    except Exception:  # network, auth or API shape errors: unknown, never noisy
        return 1
    if status is None:
        return 1
    print(status)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
