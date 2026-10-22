"""Cache-first lookup across sources."""

from contextlib import redirect_stderr
import io
import json
from pathlib import Path
import tempfile
import time
from unittest import mock
from urllib.error import HTTPError, URLError
import urllib.parse
import urllib.request

from .fixtures import LyricsCase, DAY, NOW, track, candidate, response, netease_song, netease_search
from lyrics_pkg.cache import LyricsCache
from lyrics_pkg.lookup import lookup_lyrics


class LookupTests(LyricsCase):
    def test_network_failure_preserves_stale_success_without_negative_cache(self):
        with tempfile.TemporaryDirectory() as root:
            cache = LyricsCache(Path(root))
            cache.write(track(), [(1000, "Stale but usable")], NOW - 31 * DAY)
            with mock.patch.object(time, "time", return_value=NOW), \
                    mock.patch.object(urllib.request, "urlopen", side_effect=URLError("offline")), \
                    redirect_stderr(io.StringIO()):
                self.assertEqual(lookup_lyrics(track(), cache).lines, [(1000, "Stale but usable")])
            entry = cache.read(track(), NOW)
            self.assertFalse(entry.fresh)
            self.assertEqual(entry.lines, [(1000, "Stale but usable")])

    def test_network_failure_on_miss_does_not_create_negative_entry(self):
        with tempfile.TemporaryDirectory() as root:
            cache = LyricsCache(Path(root))
            with mock.patch.object(urllib.request, "urlopen", side_effect=URLError("offline")), \
                    redirect_stderr(io.StringIO()):
                self.assertIsNone(lookup_lyrics(track(), cache).lines)
            self.assertIsNone(cache.read(track(), time.time()))

    def test_mixed_failure_retry_uses_earliest_provider_and_skips_lrclib_cooldown(self):
        with self.retry_environment([
            HTTPError("https://lrclib.net/api/get", 503, "Unavailable", {"Retry-After": "90"}, None),
            URLError("NetEase temporarily offline"),
            response(netease_search(netease_song())),
            response({"code": 200, "lrc": {"lyric": "[00:01]Recovered early"}}),
        ]) as env:
            cache, state, clock, requests = env
            current = track()
            key = state.update_track(current)
            self.lookup_into_state(cache, state, key, current)
            self.assertIsNone(cache.read(current, NOW))
            clock[0] = 115.199
            self.assertIsNone(state.next_lookup(clock[0]))
            clock[0] = 115.25
            self.assertEqual(state.next_lookup(clock[0]), (key, current))
            self.lookup_into_state(cache, state, key, current)
            self.assertEqual(state.output(1000), {"text": "Recovered early", "synced": True})
            self.assertEqual(requests.call_count, 4)
            hosts = [urllib.parse.urlparse(call.args[0].full_url).hostname
                     for call in requests.call_args_list]
            self.assertEqual(hosts, ["lrclib.net", "music.163.com", "music.163.com", "music.163.com"])
            self.assertLess(clock[0], 190.0)
            self.assertIsNone(state.next_lookup(10000))

    def test_legacy_negative_cache_does_not_hide_netease_lyrics(self):
        with self.retry_environment([
            response(None), response([]), response(netease_search(netease_song())),
            response({"code": 200, "lrc": {"lyric": "[00:01]New source lyric"}}),
        ]) as env:
            cache, state, clock, requests = env
            current = track()
            cache.path(current).write_text(json.dumps({
                "version": 2, "identity": ["firasat", "marcell", 248.0],
                "saved_at": NOW - 60, "lines": None,
            }), encoding="utf-8")
            key = state.update_track(current)
            self.lookup_into_state(cache, state, key, current)
            self.assertEqual(state.output(1000), {"text": "New source lyric", "synced": True})
            self.assertEqual(requests.call_count, 4)
            self.assertEqual(cache.read(current, NOW).lines, [(1000, "New source lyric")])

    def test_valid_negative_results_do_not_schedule_retry(self):
        cases = [
            [None, []],
            [candidate(synced=None), [candidate(synced=None)]],
            [candidate(instrumental=True), [candidate(instrumental=True)]],
        ]
        for replies in cases:
            with self.subTest(replies=replies), \
                    self.retry_environment([response(item) for item in replies + [netease_search()]]) as env:
                cache, state, clock, requests = env
                current = track()
                key = state.update_track(current)
                self.lookup_into_state(cache, state, key, current)
                self.assertFalse(state.output(1000)["synced"])
                self.assertIsNone(state.next_lookup(10000))
                self.assertTrue(cache.read(current, NOW).fresh)
                self.assertIsNone(cache.read(current, NOW).lines)
                self.assertEqual(requests.call_count, 3)
