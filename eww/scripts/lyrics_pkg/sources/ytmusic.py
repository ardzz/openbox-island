"""YouTube Music via the optional ytmusicapi and the ytm-player login."""

import json
import os
from pathlib import Path
import re
import subprocess

from ..lrc import valid_lines, valid_plain
from ..match import identity
from ..text import MAX_BYTES, normalize_title, single_line

VIDEO_ID = re.compile(r"[A-Za-z0-9_-]{11}")


def ytm_video_id(track):
    # ytm_player's MPRIS trackid is a constant path, so ask its CLI for the video id.
    try:
        result = subprocess.run(["ytm", "status"], capture_output=True, text=True, timeout=2, check=True)
        status = json.loads(result.stdout)
    except (OSError, subprocess.SubprocessError, ValueError, RecursionError) as error:
        raise OSError("ytm status failed: " + str(error)) from error
    current = status.get("track") if isinstance(status, dict) else None
    if not isinstance(current, dict):
        raise OSError("ytm status has no current track")
    video_id = current.get("video_id")
    title = current.get("title")
    if (not isinstance(video_id, str) or not VIDEO_ID.fullmatch(video_id)
            or not isinstance(title, str) or normalize_title(title) != identity(track)[0]):
        raise OSError("ytm status does not describe the current track")
    return video_id


def ytmusic_lyrics(track):
    """Return (synced lines, plain lines) from YouTube Music; (None, None) when it has none."""
    auth = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "ytm-player" / "auth.json"
    if not auth.is_file():
        return None, None
    try:
        from ytmusicapi import YTMusic
    except ImportError:
        return None, None
    video_id = ytm_video_id(track)
    try:
        client = YTMusic(str(auth))
        browse_id = client.get_watch_playlist(videoId=video_id, limit=1).get("lyrics")
        if not browse_id:
            return None, None
        try:
            found = client.get_lyrics(browse_id, timestamps=True)
        except Exception:
            # The timed (mobile client) request can fail with HTTP 400 where the plain one works.
            found = client.get_lyrics(browse_id, timestamps=False)
    except Exception as error:
        # ytmusicapi raises its own, requests and parsing errors; all are worth a later retry.
        raise OSError("ytmusic request failed: " + str(error)) from error
    body = found.get("lyrics") if isinstance(found, dict) else None
    if isinstance(body, list) and found.get("hasTimestamps") is True:
        try:
            lines = sorted(((row.start_time, single_line(row.text)) for row in body), key=lambda row: row[0])
        except (AttributeError, TypeError):
            lines = None
        return (lines if valid_lines(lines) else None), None
    if isinstance(body, str) and len(body) <= MAX_BYTES:
        plain = [line for line in map(single_line, body.splitlines()) if line]
        return None, (plain if valid_plain(plain) else None)
    return None, None
