"""YouTube Music fixtures: recorded API shapes, a fake ytmusicapi and the ytm environment."""

from contextlib import contextmanager
from dataclasses import dataclass
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import types
from unittest import mock

from .fixtures import LyricsCase, response, track
from lyrics_pkg.lookup import lookup_lyrics
from lyrics_pkg.sources import ytmusic

# Shapes probed read-only on the real account with ytmusicapi 1.12.3 (2026-10-22): every queued
# track returned HTTP 400 for timestamps=True and a plain string for timestamps=False.
YTM_STATUS = {
    "track": {"video_id": "k9CTIUM9RmA", "title": "Sun Shower", "artist": "The Poles",
              "artists": [{"name": "The Poles", "id": "UCAodJxXWk1WS9Ko57bRF-ug"}],
              "album": "Sun Shower", "album_id": "MPREb_sFZ3WK0rGCU", "duration": 283,
              "is_video": False, "likeStatus": None, "setVideoId": None},
    "is_playing": True, "is_paused": False, "volume": 80, "position": 11.4,
    "duration": 282.261, "repeat": "off", "shuffle": False, "queue_length": 25,
}
YTM_WATCH = {
    "tracks": [{"videoId": "k9CTIUM9RmA", "title": "Sun Shower", "length": "4:43",
                "likeStatus": "INDIFFERENT"}],
    "playlistId": "RDAMVMk9CTIUM9RmA", "lyrics": "MPLYt_sFZ3WK0rGCU-1",
    "related": "MPTRt_sFZ3WK0rGCU-1",
}
YTM_PLAIN = {"lyrics": "비가 와요\n기다린 만큼 흘러 넘치게\n\n오, 오오오오\n아직도 넌 끝이 없고",
             "source": None, "hasTimestamps": False}


class YTMusicServerError(Exception):
    pass


@dataclass
class LyricLine:
    text: str
    start_time: int
    end_time: int
    id: int


# Timed shape from the ytmusicapi 1.12.3 get_lyrics contract (the account never produced one).
YTM_TIMED = {"lyrics": [LyricLine("I gave in to the fire", 10680, 12540, 2),
                        LyricLine("I was a liar", 9200, 10630, 1)],
             "source": "Source: LyricFind", "hasTimestamps": True}
YTM_400 = YTMusicServerError("Server returned HTTP 400: Bad Request.\nRequest contains an invalid argument.")


def ytm_track(title="Sun Shower", artist="The Poles", length=282, player="ytm_player"):
    return track(title=title, artist=artist, length=length, player=player)


def fake_ytmusicapi(watch=YTM_WATCH, timed=YTM_400, plain=YTM_PLAIN):
    calls = []

    def reply(value):
        if isinstance(value, BaseException):
            raise value
        return value

    class YTMusic:
        def __init__(self, auth=None, *args, **kwargs):
            calls.append(("init", str(auth)))

        def get_watch_playlist(self, videoId=None, limit=25, **kwargs):
            calls.append(("watch", videoId, limit))
            return reply(watch)

        def get_lyrics(self, browseId, timestamps=False):
            calls.append(("lyrics", browseId, timestamps))
            return reply(timed if timestamps else plain)

    module = types.ModuleType("ytmusicapi")
    module.YTMusic = YTMusic
    return module, calls


ALL_MISSES = (None, [], {"code": 200, "result": {"songs": []}})


class YtmCase(LyricsCase):
    @contextmanager
    def ytm_environment(self, replies=(), ytmusicapi=None, status=YTM_STATUS, auth=True):
        module, calls = ytmusicapi if ytmusicapi is not None else fake_ytmusicapi()
        status_calls = []

        def run(args, **kwargs):
            status_calls.append(list(args))
            self.assertEqual(list(args), ["ytm", "status"])
            self.assertIsNotNone(kwargs.get("timeout"))
            if isinstance(status, BaseException):
                raise status
            stdout = status if isinstance(status, str) else json.dumps(status)
            return subprocess.CompletedProcess(args, 0, stdout=stdout, stderr="")

        with tempfile.TemporaryDirectory() as config, \
                mock.patch.dict(sys.modules, {"ytmusicapi": module}), \
                mock.patch.dict(ytmusic.os.environ, {"XDG_CONFIG_HOME": config}), \
                mock.patch.object(ytmusic.subprocess, "run", side_effect=run), \
                self.retry_environment([item if isinstance(item, BaseException) else response(item)
                                        for item in replies]) as (cache, state, clock, requests):
            auth_path = Path(config) / "ytm-player" / "auth.json"
            if auth:
                auth_path.parent.mkdir()
                auth_path.write_text("{}", encoding="utf-8")
            yield types.SimpleNamespace(cache=cache, state=state, clock=clock, requests=requests,
                                        calls=calls, status_calls=status_calls, auth=auth_path,
                                        stderr=self.stderr)

    def ytm_lookup(self, env, current):
        key = env.state.update_track(current)
        result = lookup_lyrics(current, env.cache)
        env.state.accept_lookup(key, *result)
        return result
