"""Shared fixtures for the lyrics package tests."""

from contextlib import contextmanager, redirect_stderr
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

SCRIPTS = Path(__file__).resolve().parents[2] / "eww" / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from lyrics_pkg import http as lyrics_http  # noqa: E402
from lyrics_pkg.cache import LyricsCache  # noqa: E402
from lyrics_pkg.lookup import lookup_lyrics  # noqa: E402
from lyrics_pkg.state import LyricsState  # noqa: E402

DAY = 24 * 60 * 60
NOW = 1_800_000_000


def track(title="Firasat", artist="Marcell", length=248, player="fixture"):
    return {"state": "playing", "player": player, "title": title,
            "artist": artist, "length": length}


def candidate(title="Firasat", artist="Marcell", duration=248,
              synced="[00:01.00]A line", instrumental=False):
    return {"id": 1, "name": title, "trackName": title,
            "artistName": artist, "albumName": "Fixture album",
            "duration": duration, "instrumental": instrumental,
            "plainLyrics": "A line", "syncedLyrics": synced}


def response(payload):
    return io.BytesIO(json.dumps(payload).encode("utf-8"))


def netease_song(song_id=101, title="Firasat", artist="Marcell", duration=248000, aliases=()):
    return {"id": song_id, "name": title, "duration": duration,
            "artists": [{"name": artist, "alias": list(aliases)}]}


def netease_search(*songs):
    return {"code": 200, "result": {"songs": list(songs)}}


class LyricsCase(unittest.TestCase):
    """Fake clock, request spacing/cooldown state and network for lookup tests."""

    @contextmanager
    def retry_environment(self, replies):
        clock = [100.0]

        def advance(seconds):
            clock[0] += seconds

        self.stderr = io.StringIO()
        with tempfile.TemporaryDirectory() as root, \
                mock.patch.object(lyrics_http, "_next_request", 0.0), \
                mock.patch.object(lyrics_http, "_cooldowns", {"lrclib": 0.0, "netease": 0.0}), \
                mock.patch.object(lyrics_http.time, "monotonic", side_effect=lambda: clock[0]), \
                mock.patch.object(lyrics_http.time, "time", return_value=NOW), \
                mock.patch.object(lyrics_http.time, "sleep", side_effect=advance), \
                mock.patch.object(lyrics_http.urllib.request, "urlopen", side_effect=replies) as requests, \
                redirect_stderr(self.stderr):
            yield LyricsCache(root), LyricsState(), clock, requests

    def lookup_into_state(self, cache, state, key, current):
        result = lookup_lyrics(current, cache)
        state.accept_lookup(key, result.lines, result.retry_at)
