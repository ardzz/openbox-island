"""LRCLIB get/search source."""

from pathlib import Path
import tempfile
import time
from unittest import mock
import urllib.request

from .fixtures import LyricsCase, NOW, track, candidate, response, netease_search
from lyrics_pkg.cache import LyricsCache
from lyrics_pkg.lookup import lookup_lyrics


class LrclibTests(LyricsCase):
    def test_artist_names_lookup_selects_synced_parenthetical_artist_over_plain_exact_artist(self):
        current = track(title="High Tide", artist="The Poles", length=248)
        with self.retry_environment([
            response(candidate(title="High Tide", artist="The Poles", synced=None)),
            response([
                candidate(title="High Tide", artist="The Poles", synced=None),
                candidate(title="High Tide", artist="The Poles (더 폴스)", duration=249,
                          synced="[00:01.25]High Tide lyric"),
            ]),
        ]) as env:
            cache, state, clock, requests = env
            key = state.update_track(current)
            self.lookup_into_state(cache, state, key, current)
            self.assert_line(state, 1250, "High Tide lyric", True)
            self.assertEqual(requests.call_count, 2)
            self.assertEqual(cache.read(current, NOW).lines, [(1250, "High Tide lyric")])

    def test_plain_get_searches_for_closest_synced_and_caches_it(self):
        with tempfile.TemporaryDirectory() as root:
            cache = LyricsCache(Path(root))
            with mock.patch.object(urllib.request, "urlopen", side_effect=[
                response(candidate(synced=None)),
                response([candidate(duration=250, synced="[00:01]Far"),
                          candidate(duration=248, synced="[00:01]Found")]),
            ]):
                lines = lookup_lyrics(track(), cache).lines
            self.assertEqual(lines, [(1000, "Found")])
            cached = cache.read(track(), time.time())
            self.assertTrue(cached.fresh)
            self.assertEqual(cached.lines, [(1000, "Found")])

    def test_actual_plain_only_result_is_negative_cached(self):
        with tempfile.TemporaryDirectory() as root:
            cache = LyricsCache(Path(root))
            with mock.patch.object(urllib.request, "urlopen", side_effect=[
                response(candidate(synced=None)), response([candidate(synced=None)]),
                response(netease_search()),
            ]):
                self.assertIsNone(lookup_lyrics(track(), cache).lines)
            entry = cache.read(track(), time.time())
            self.assertTrue(entry.fresh)
            self.assertIsNone(entry.lines)

    def test_netease_is_not_consulted_after_lrclib_hit(self):
        with self.retry_environment([response(candidate())]) as env:
            cache, state, clock, requests = env
            result = lookup_lyrics(track(), cache)
            self.assertEqual(result.lines, [(1000, "A line")])
            self.assertEqual(requests.call_count, 1)
