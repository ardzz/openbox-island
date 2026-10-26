"""YouTube Music source for ytm_player."""

import json
import subprocess

from .fixtures import DAY, NOW, track, candidate, netease_song, netease_search
from .ytm_fixtures import (ALL_MISSES, YTM_400, YTM_PLAIN, YTM_STATUS, YTM_TIMED, YTM_WATCH,
                           YTMusicServerError, YtmCase, fake_ytmusicapi, ytm_track)
from lyrics_pkg.lookup import lookup_lyrics


class YtmusicTests(YtmCase):
    def test_ytm_timed_lyrics_are_first_and_skip_other_sources(self):
        with self.ytm_environment(ytmusicapi=fake_ytmusicapi(timed=YTM_TIMED)) as env:
            current = ytm_track()
            self.ytm_lookup(env, current)
            self.assert_line(env.state, 9199, "Sun Shower — The Poles", False)
            self.assert_line(env.state, 9200, "I was a liar", True)
            self.assert_line(env.state, 11000, "I gave in to the fire", True)
            self.assertEqual(env.requests.call_count, 0)
            self.assertEqual(env.status_calls, [["ytm", "status"]])
            self.assertEqual(env.calls, [("init", str(env.auth)), ("watch", "k9CTIUM9RmA", 1),
                                         ("lyrics", "MPLYt_sFZ3WK0rGCU-1", True)])
            self.assertEqual(env.cache.read(current, NOW).lines,
                             [(9200, "I was a liar"), (10680, "I gave in to the fire")])
            self.assertEqual(env.stderr.getvalue(), "")

    def test_ytm_timestamp_400_retries_plain_which_loses_to_lrclib_synced(self):
        lrclib = candidate(title="Sun Shower", artist="The Poles", duration=282, synced="[00:01]From LRCLIB")
        with self.ytm_environment([lrclib]) as env:
            result = self.ytm_lookup(env, ytm_track())
            self.assertEqual(result.lines, [(1000, "From LRCLIB")])
            self.assert_line(env.state, 1000, "From LRCLIB", True)
            self.assertEqual(env.calls[-2:], [("lyrics", "MPLYt_sFZ3WK0rGCU-1", True),
                                              ("lyrics", "MPLYt_sFZ3WK0rGCU-1", False)])
            self.assertEqual(env.requests.call_count, 1)
            self.assertEqual(env.cache.read(ytm_track(), NOW).lines, [(1000, "From LRCLIB")])

    def test_netease_synced_beats_ytm_plain(self):
        with self.ytm_environment([
            None, [], netease_search(netease_song(title="Sun Shower", artist="The Poles", duration=282000)),
            {"code": 200, "lrc": {"lyric": "[00:01]From NetEase"}},
        ]) as env:
            result = self.ytm_lookup(env, ytm_track())
            self.assertEqual(result.lines, [(1000, "From NetEase")])
            self.assert_line(env.state, 1000, "From NetEase", True)
            self.assertEqual(env.requests.call_count, 4)

    def test_ytm_plain_is_unsynced_estimated_by_position_and_negative_cached_for_a_day(self):
        plain = ["비가 와요", "기다린 만큼 흘러 넘치게", "오, 오오오오", "아직도 넌 끝이 없고"]
        with self.ytm_environment(ALL_MISSES) as env:
            current = ytm_track(length=240)
            result = self.ytm_lookup(env, current)
            self.assertIsNone(result.lines)
            self.assertIsNone(result.retry_at)
            self.assertEqual(env.requests.call_count, 3)
            self.assert_line(env.state, None, "Sun Shower — The Poles", False)
            for position, index in [(0, 0), (59999, 0), (60000, 1), (179999, 2),
                                    (180000, 3), (239999, 3), (500000, 3)]:
                with self.subTest(position=position):
                    self.assert_line(env.state, position, plain[index], False)
            entry = env.cache.read(current, NOW + DAY - 1)
            self.assertTrue(entry.fresh)
            self.assertIsNone(entry.lines)
            self.assertEqual(entry.plain, plain)
            self.assertFalse(env.cache.read(current, NOW + DAY).fresh)
            self.assertEqual(env.stderr.getvalue(), "")

    def test_plain_lyrics_from_timestamped_request_need_no_second_request(self):
        with self.ytm_environment(ALL_MISSES, ytmusicapi=fake_ytmusicapi(timed=YTM_PLAIN)) as env:
            self.ytm_lookup(env, ytm_track(length=240))
            self.assert_line(env.state, 0, "비가 와요", False)
            self.assertEqual([call for call in env.calls if call[0] == "lyrics"],
                             [("lyrics", "MPLYt_sFZ3WK0rGCU-1", True)])

    def test_negative_cache_without_ytm_does_not_hide_ytm_lyrics(self):
        with self.ytm_environment(ALL_MISSES) as env:
            current = ytm_track(length=240)
            env.cache.path(current).write_text(json.dumps({
                "version": 2, "identity": ["sun shower", "the poles", 240.0],
                "saved_at": NOW - 60, "lines": None, "negative": ["lrclib", "netease"],
            }), encoding="utf-8")
            self.assertTrue(env.cache.read(ytm_track(length=240, player="spotify"), NOW).fresh)
            self.assertIsNone(env.cache.read(current, NOW))
            self.ytm_lookup(env, current)
            self.assert_line(env.state, 0, "비가 와요", False)
            self.assertIn(("watch", "k9CTIUM9RmA", 1), env.calls)

    def test_other_players_never_consult_ytm(self):
        with self.ytm_environment([candidate()]) as env:
            result = self.ytm_lookup(env, track(player="spotify"))
            self.assertEqual(result.lines, [(1000, "A line")])
            self.assertEqual(env.status_calls, [])
            self.assertEqual(env.calls, [])

    def test_missing_ytmusicapi_or_auth_skips_ytm_silently(self):
        lrclib = candidate(title="Sun Shower", artist="The Poles", duration=282)
        for name, options in [("module", {"ytmusicapi": (None, [])}), ("auth", {"auth": False})]:
            with self.subTest(missing=name), self.ytm_environment([lrclib], **options) as env:
                result = self.ytm_lookup(env, ytm_track())
                self.assertEqual(result.lines, [(1000, "A line")])
                self.assertEqual(env.status_calls, [])
                self.assertEqual(env.calls, [])
                self.assertEqual(env.stderr.getvalue(), "")

    def test_unavailable_ytm_still_negative_caches_definitive_misses(self):
        with self.ytm_environment(ALL_MISSES, ytmusicapi=(None, [])) as env:
            result = self.ytm_lookup(env, ytm_track())
            self.assertIsNone(result.lines)
            self.assertIsNone(result.retry_at)
            self.assertTrue(env.cache.read(ytm_track(), NOW).fresh)

    def test_unknown_video_id_skips_ytm_and_schedules_retry(self):
        cases = [
            FileNotFoundError("ytm"),
            subprocess.TimeoutExpired(["ytm", "status"], 2),
            "not json",
            {"track": None, "is_playing": False},
            dict(YTM_STATUS, track=dict(YTM_STATUS["track"], title="Another song")),
            dict(YTM_STATUS, track=dict(YTM_STATUS["track"], video_id="../bad")),
        ]
        for status in cases:
            with self.subTest(status=status), self.ytm_environment(ALL_MISSES, status=status) as env:
                result = self.ytm_lookup(env, ytm_track())
                self.assertIsNone(result.lines)
                self.assertIsNotNone(result.retry_at)
                self.assertNotIn("watch", [call[0] for call in env.calls])
                self.assertEqual(env.requests.call_count, 3)
                self.assertIsNone(env.cache.read(ytm_track(), NOW))
                self.assertIn("lyrics: ytmusic lookup failed", env.stderr.getvalue())

    def test_ytm_request_failure_is_transient(self):
        for options in [{"watch": ConnectionError("offline")},
                        {"watch": YTMusicServerError("Server returned HTTP 503")},
                        {"plain": YTM_400}]:
            with self.subTest(options=options), \
                    self.ytm_environment(ALL_MISSES, ytmusicapi=fake_ytmusicapi(**options)) as env:
                current = ytm_track()
                key = env.state.update_track(current)
                result = lookup_lyrics(current, env.cache)
                env.state.accept_lookup(key, *result)
                self.assertIsNone(result.lines)
                self.assertIsNotNone(result.retry_at)
                self.assertIsNone(env.cache.read(current, NOW))
                # Three spaced requests end at 100.4, so the first retry is due at 115.4.
                self.assertIsNone(env.state.next_lookup(115.3))
                env.clock[0] = 115.5
                self.assertEqual(env.state.next_lookup(env.clock[0]), (key, current))

    def test_ytm_without_lyrics_is_a_definitive_miss(self):
        for options in [{"watch": dict(YTM_WATCH, lyrics=None)},
                        {"watch": {key: value for key, value in YTM_WATCH.items() if key != "lyrics"}},
                        {"plain": None}]:
            with self.subTest(options=options), \
                    self.ytm_environment(ALL_MISSES, ytmusicapi=fake_ytmusicapi(**options)) as env:
                result = self.ytm_lookup(env, ytm_track())
                self.assertIsNone(result.lines)
                self.assertIsNone(result.retry_at)
                entry = env.cache.read(ytm_track(), NOW)
                self.assertTrue(entry.fresh)
                self.assertIsNone(entry.plain)
                self.assert_line(env.state, 0, "Sun Shower — The Poles", False)
