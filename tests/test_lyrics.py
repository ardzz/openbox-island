"""Consumer contracts for the standalone lyrics listener (stdlib plus optional ytmusicapi)."""

from contextlib import contextmanager, redirect_stderr
from dataclasses import dataclass
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import types
import unittest
from unittest import mock
from urllib.error import HTTPError, URLError


SCRIPT = Path(__file__).resolve().parents[1] / "eww" / "scripts" / "lyrics.py"
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


class LyricsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not SCRIPT.is_file():
            raise AssertionError("Live lyrics feature is missing: eww/scripts/lyrics.py")
        spec = importlib.util.spec_from_file_location("island_lyrics", SCRIPT)
        cls.lyrics = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = cls.lyrics
        spec.loader.exec_module(cls.lyrics)

    def test_lrc_fractional_multiple_timestamps_and_metadata(self):
        lines = self.lyrics.parse_lrc(
            "[ar:Marcell]\n[ti:Firasat]\n"
            "[00:01.2][00:03.045]Repeated\n[00:02.34]Middle\n"
            "not timed\n[00:04.000]\n"
        )
        self.assertEqual(lines, [(1200, "Repeated"), (2340, "Middle"),
                                 (3045, "Repeated"), (4000, "")])

    def test_line_choice_intro_boundary_blank_and_seek(self):
        lines = [(1200, "First"), (2340, "Second"), (4000, ""), (5000, "Last")]
        for position, expected in [(0, None), (1199, None), (1200, "First"),
                                   (2339, "First"), (2340, "Second"),
                                   (4000, ""), (4999, ""), (5000, "Last"),
                                   (1500, "First")]:
            with self.subTest(position=position):
                self.assertEqual(self.lyrics.line_at(lines, position), expected)

    def test_lrc_positive_offset_advances_line_and_negative_delays_it(self):
        advanced = self.lyrics.parse_lrc("[offset:250]\n[00:01.00]Advanced")
        self.assertEqual(advanced, [(750, "Advanced")])
        self.assertIsNone(self.lyrics.line_at(advanced, 749))
        self.assertEqual(self.lyrics.line_at(advanced, 750), "Advanced")
        delayed = self.lyrics.parse_lrc("[00:01.00]Delayed\n[offset:-250]")
        self.assertEqual(delayed, [(1250, "Delayed")])
        self.assertIsNone(self.lyrics.line_at(delayed, 1249))
        self.assertEqual(self.lyrics.line_at(delayed, 1250), "Delayed")

    def test_lrc_offset_preserves_negative_effective_timestamps(self):
        lines = self.lyrics.parse_lrc("[offset:1250]\n[00:01.00]Already active")
        self.assertEqual(lines, [(-250, "Already active")])
        self.assertIsNone(self.lyrics.line_at(lines, -251))
        self.assertEqual(self.lyrics.line_at(lines, -250), "Already active")
        self.assertEqual(self.lyrics.line_at(lines, 0), "Already active")

    def test_normalization_removes_only_promotional_suffixes(self):
        cases = [
            ("  Firasat  (Official Music Video) ", "firasat"),
            ("Firasat - OFFICIAL AUDIO", "firasat"),
            ("Firasat [Lyrics]", "firasat"),
            (" Firasat\u00a0 Live (Official Video)", "firasat live"),
            ("Firasat (Remix)", "firasat (remix)"),
            ("A - B (feat. C)", "a - b (feat. c)"),
            ("Firasat (Acoustic)", "firasat (acoustic)"),
            ("Firasat (Instrumental)", "firasat (instrumental)"),
            ("Firasat - slowed", "firasat - slowed"),
            ("Firasat - sped-up", "firasat - sped-up"),
        ]
        for value, expected in cases:
            with self.subTest(value=value):
                self.assertEqual(self.lyrics.normalize_title(value), expected)
        self.assertEqual(self.lyrics.normalize_artist("  Marcell - Topic  "), "marcell")
        self.assertEqual(self.lyrics.normalize_artist("Topic - Marcell"), "topic - marcell")

    def test_match_chooses_closest_strict_synced_candidate(self):
        choices = [candidate(duration=246, synced="[00:01]Far"),
                   candidate(duration=248.5, synced="[00:01]Closest"),
                   candidate(duration=249, synced="[00:01]Near")]
        selected = self.lyrics.choose_candidate(track(), choices)
        self.assertEqual(selected["syncedLyrics"], "[00:01]Closest")

    def test_match_rejects_wrong_identity_version_duration_and_plain(self):
        bad = [candidate(artist="Another artist"), candidate(title="Another song"),
               candidate(title="Firasat (Live)"), candidate(title="Firasat (Remix)"),
               candidate(duration=245.999), candidate(duration=250.001),
               candidate(duration=None), candidate(duration=True),
               candidate(duration=float("nan")), candidate(synced=None),
               candidate(synced="plain words"), candidate(instrumental=True)]
        for item in bad:
            with self.subTest(item=item):
                self.assertIsNone(self.lyrics.choose_candidate(track(), [item]))
        for duration in [246, 250]:
            with self.subTest(boundary=duration):
                self.assertIsNotNone(self.lyrics.choose_candidate(track(), [candidate(duration=duration)]))
        for duration in [None, 0, True, float("nan")]:
            with self.subTest(track_duration=duration):
                self.assertIsNone(self.lyrics.choose_candidate(track(length=duration), [candidate()]))

    def test_matching_accepts_clean_topic_and_promo_without_losing_version(self):
        selected = self.lyrics.choose_candidate(
            track(title="Firasat (Live) [Official Video]", artist="Marcell - Topic"),
            [candidate(title="Firasat"), candidate(title="Firasat (Live)")])
        self.assertEqual(selected["trackName"], "Firasat (Live)")

    def test_artist_names_match_aliases_and_top_level_collaborators_for_both_sources(self):
        cases = [
            ("The Poles", "The Poles (더 폴스)", True),
            ("이희상 (LEEHEESANG)", "LEEHEESANG", True),
            ("이희상 [LEEHEESANG]", "LEEHEESANG", True),
            ("A, B", "B", True),
            ("A & B", "A", True),
            ("A x B", "B", True),
            ("A × B", "A", True),
            ("A / B", "B", True),
            ("A feat. B", "B", True),
            ("A ft. B", "B", True),
            ("A featuring B", "B", True),
            ("A with B", "B", True),
            ("A, B (비)", "B", True),
            ("AB", "A", False),
            ("Hall & Oates", "Hall & Oates", True),
            ("A - B", "A", False),
            ("A and B", "B", False),
            ("A", "Band (A, B)", False),
            ("The Poles - Topic", "The Poles (더 폴스)", True),
        ]
        for ours, theirs, accepted in cases:
            for our_artist, candidate_artist in ((ours, theirs), (theirs, ours)):
                with self.subTest(ours=our_artist, candidate=candidate_artist):
                    current = track(artist=our_artist)
                    lrclib = self.lyrics.choose_candidate(
                        current, [candidate(artist=candidate_artist, duration=249.5)])
                    netease = self.lyrics.choose_netease_candidate(
                        current, [netease_song(artist=candidate_artist, duration=249500)])
                    self.assertEqual(lrclib is not None, accepted)
                    self.assertEqual(netease is not None, accepted)

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
            self.assertEqual(state.output(1250), {"text": "High Tide lyric", "synced": True})
            self.assertEqual(requests.call_count, 2)
            self.assertEqual(cache.read(current, NOW).lines, [(1250, "High Tide lyric")])

    def test_positive_cache_freshness_and_stale_lines(self):
        with tempfile.TemporaryDirectory() as root:
            cache = self.lyrics.LyricsCache(Path(root))
            cache.write(track(), [(1000, "Cached")], NOW)
            self.assertTrue(cache.read(track(), NOW + 30 * DAY - 1).fresh)
            stale = cache.read(track(), NOW + 30 * DAY + 1)
            self.assertFalse(stale.fresh)
            self.assertEqual(stale.lines, [(1000, "Cached")])

    def test_negative_cache_expires_after_one_day(self):
        with tempfile.TemporaryDirectory() as root:
            cache = self.lyrics.LyricsCache(Path(root))
            cache.write(track(), None, NOW)
            self.assertTrue(cache.read(track(), NOW + DAY - 1).fresh)
            self.assertIsNone(cache.read(track(), NOW + DAY - 1).lines)
            self.assertFalse(cache.read(track(), NOW + DAY + 1).fresh)

    def test_old_parsed_cache_version_is_a_miss(self):
        with tempfile.TemporaryDirectory() as root:
            cache = self.lyrics.LyricsCache(Path(root))
            cache.write(track(), [(1250, "Old offset direction")], NOW)
            files = list(Path(root).glob("*.json"))
            self.assertEqual(len(files), 1)
            data = json.loads(files[0].read_text(encoding="utf-8"))
            data["version"] = 1
            files[0].write_text(json.dumps(data), encoding="utf-8")
            self.assertIsNone(cache.read(track(), NOW))

    def test_cache_identity_uses_clean_metadata_and_duration_not_player(self):
        with tempfile.TemporaryDirectory() as root:
            cache = self.lyrics.LyricsCache(Path(root))
            cache.write(track(), [(1000, "Cached")], NOW)
            same = track(title="Firasat [Official Audio]", artist="Marcell - Topic", player="other")
            self.assertEqual(cache.read(same, NOW).lines, [(1000, "Cached")])
            for other in [track(title="Firasat (Live)"), track(artist="Other"), track(length=249)]:
                self.assertIsNone(cache.read(other, NOW))

    def test_corrupt_or_mismatched_cache_is_a_miss(self):
        with tempfile.TemporaryDirectory() as root:
            cache = self.lyrics.LyricsCache(Path(root))
            cache.write(track(), [(1000, "Cached")], NOW)
            files = list(Path(root).glob("*.json"))
            self.assertEqual(len(files), 1)
            original = files[0].read_text(encoding="utf-8")
            files[0].write_text("{broken", encoding="utf-8")
            self.assertIsNone(cache.read(track(), NOW))
            data = json.loads(original)
            data["lines"] = [["not a timestamp", "Bad"]]
            files[0].write_text(json.dumps(data), encoding="utf-8")
            self.assertIsNone(cache.read(track(), NOW))
            files[0].write_text(original.replace("firasat", "other song"), encoding="utf-8")
            self.assertIsNone(cache.read(track(), NOW))

    def test_plain_get_searches_for_closest_synced_and_caches_it(self):
        with tempfile.TemporaryDirectory() as root:
            cache = self.lyrics.LyricsCache(Path(root))
            with mock.patch.object(self.lyrics.urllib.request, "urlopen", side_effect=[
                response(candidate(synced=None)),
                response([candidate(duration=250, synced="[00:01]Far"),
                          candidate(duration=248, synced="[00:01]Found")]),
            ]):
                lines = self.lyrics.lookup_lyrics(track(), cache).lines
            self.assertEqual(lines, [(1000, "Found")])
            cached = cache.read(track(), self.lyrics.time.time())
            self.assertTrue(cached.fresh)
            self.assertEqual(cached.lines, [(1000, "Found")])

    def test_actual_plain_only_result_is_negative_cached(self):
        with tempfile.TemporaryDirectory() as root:
            cache = self.lyrics.LyricsCache(Path(root))
            with mock.patch.object(self.lyrics.urllib.request, "urlopen", side_effect=[
                response(candidate(synced=None)), response([candidate(synced=None)]),
                response(netease_search()),
            ]):
                self.assertIsNone(self.lyrics.lookup_lyrics(track(), cache).lines)
            entry = cache.read(track(), self.lyrics.time.time())
            self.assertTrue(entry.fresh)
            self.assertIsNone(entry.lines)

    def test_network_failure_preserves_stale_success_without_negative_cache(self):
        with tempfile.TemporaryDirectory() as root:
            cache = self.lyrics.LyricsCache(Path(root))
            cache.write(track(), [(1000, "Stale but usable")], NOW - 31 * DAY)
            with mock.patch.object(self.lyrics.time, "time", return_value=NOW), \
                    mock.patch.object(self.lyrics.urllib.request, "urlopen", side_effect=URLError("offline")), \
                    redirect_stderr(io.StringIO()):
                self.assertEqual(self.lyrics.lookup_lyrics(track(), cache).lines, [(1000, "Stale but usable")])
            entry = cache.read(track(), NOW)
            self.assertFalse(entry.fresh)
            self.assertEqual(entry.lines, [(1000, "Stale but usable")])

    def test_network_failure_on_miss_does_not_create_negative_entry(self):
        with tempfile.TemporaryDirectory() as root:
            cache = self.lyrics.LyricsCache(Path(root))
            with mock.patch.object(self.lyrics.urllib.request, "urlopen", side_effect=URLError("offline")), \
                    redirect_stderr(io.StringIO()):
                self.assertIsNone(self.lyrics.lookup_lyrics(track(), cache).lines)
            self.assertIsNone(cache.read(track(), self.lyrics.time.time()))

    @contextmanager
    def retry_environment(self, replies):
        clock = [100.0]

        def advance(seconds):
            clock[0] += seconds

        self.stderr = io.StringIO()
        with tempfile.TemporaryDirectory() as root, \
                mock.patch.object(self.lyrics, "_next_request", 0.0), \
                mock.patch.object(self.lyrics, "_cooldowns", {"lrclib": 0.0, "netease": 0.0}), \
                mock.patch.object(self.lyrics.time, "monotonic", side_effect=lambda: clock[0]), \
                mock.patch.object(self.lyrics.time, "time", return_value=NOW), \
                mock.patch.object(self.lyrics.time, "sleep", side_effect=advance), \
                mock.patch.object(self.lyrics.urllib.request, "urlopen", side_effect=replies) as requests, \
                redirect_stderr(self.stderr):
            yield self.lyrics.LyricsCache(root), self.lyrics.LyricsState(), clock, requests

    def lookup_into_state(self, cache, state, key, current):
        result = self.lyrics.lookup_lyrics(current, cache)
        state.accept_lookup(key, result.lines, result.retry_at)

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
            hosts = [self.lyrics.urllib.parse.urlparse(call.args[0].full_url).hostname
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

    def test_netease_cooldown_is_separate_but_request_spacing_is_global(self):
        with self.retry_environment([]) as env:
            cache, state, clock, requests = env
            starts = []
            replies = iter([
                response(None),
                HTTPError("https://music.163.com/api/search/get", 503, "Unavailable",
                          {"Retry-After": "90"}, None),
                response([]),
            ])

            def fetch(request, timeout):
                starts.append(clock[0])
                self.assertEqual(timeout, 5)
                self.assertEqual(request.get_header("User-agent"), "openbox-island/1.0 (+https://github.com/ardzz/openbox-island)")
                self.assertIsNone(request.get_header("Cookie"))
                reply = next(replies)
                if isinstance(reply, Exception):
                    raise reply
                return reply

            requests.side_effect = fetch
            self.assertIsNone(self.lyrics.request_json("get", {}))
            with self.assertRaises(HTTPError):
                self.lyrics.request_json("search/get", {}, source="netease")
            self.assertEqual(self.lyrics.request_json("search", {}), [])
            with self.assertRaises(OSError):
                self.lyrics.request_json("search/get", {}, source="netease")
            self.assertEqual(len(starts), 3)
            for actual, expected in zip(starts, (100.0, 100.2, 100.4)):
                self.assertAlmostEqual(actual, expected)
            self.assertEqual(requests.call_count, 3)

    def test_netease_fallback_after_lrclib_not_found_or_plain_only(self):
        for first in (
            HTTPError("https://lrclib.net/api/get", 404, "Not found", {}, None),
            response(candidate(synced=None)),
        ):
            with self.subTest(first=first), self.retry_environment([
                first, response([]), response(netease_search(netease_song())),
                response({"code": 200, "lrc": {"lyric": "[00:01]Fallback"}}),
            ]) as env:
                cache, state, clock, requests = env
                key = state.update_track(track())
                self.lookup_into_state(cache, state, key, track())
                self.assertEqual(state.output(1000), {"text": "Fallback", "synced": True})
                self.assertEqual(cache.read(track(), NOW).lines, [(1000, "Fallback")])
                self.assertTrue(requests.call_args_list[2].args[0].full_url.startswith(
                    "https://music.163.com/api/search/get?"))
                self.assertTrue(requests.call_args_list[3].args[0].full_url.startswith(
                    "https://music.163.com/api/song/lyric?"))

    def test_netease_is_not_consulted_after_lrclib_hit(self):
        with self.retry_environment([response(candidate())]) as env:
            cache, state, clock, requests = env
            result = self.lyrics.lookup_lyrics(track(), cache)
            self.assertEqual(result.lines, [(1000, "A line")])
            self.assertEqual(requests.call_count, 1)

    def test_netease_cross_script_requires_unique_exact_title_and_one_second_duration(self):
        current = track(title="How to fall in love", artist="LEEHEESANG", length=182)
        good = netease_song(title="How to fall in love", artist="이희상", duration=183000)
        cases = [
            ([good], True),
            ([good, dict(good, id=102, duration=182000)], False),
            ([dict(good, duration=183001)], False),
            ([dict(good, name="How to fall in love (Live)")], False),
        ]
        for songs, accepted in cases:
            replies = [response(None), response([]), response(netease_search(*songs))]
            if accepted:
                replies.append(response({"code": 200, "lrc": {"lyric": "[00:01]Matched"}}))
            with self.subTest(songs=songs), self.retry_environment(replies) as env:
                cache, state, clock, requests = env
                result = self.lyrics.lookup_lyrics(current, cache)
                self.assertEqual(result.lines, [(1000, "Matched")] if accepted else None)
                self.assertIsNone(result.retry_at)
                self.assertEqual(requests.call_count, 4 if accepted else 3)

    def test_netease_artist_names_and_aliases_allow_two_second_duration(self):
        cases = [
            (netease_song(duration=250000), True),
            (netease_song(artist="마르셀", aliases=["Marcell"], duration=246000), True),
            (netease_song(duration=250001), False),
        ]
        for song, accepted in cases:
            replies = [response(None), response([]), response(netease_search(song))]
            if accepted:
                replies.append(response({"code": 200, "lrc": {"lyric": "[00:01]Matched"}}))
            with self.subTest(song=song), self.retry_environment(replies) as env:
                cache, state, clock, requests = env
                result = self.lyrics.lookup_lyrics(track(artist="Marcell - Topic"), cache)
                self.assertEqual(result.lines, [(1000, "Matched")] if accepted else None)

    def test_netease_filters_credit_labels_without_changing_timestamps(self):
        labels = ["作词", "作曲", "编曲", "制作人", "监制", "混音", "母带", "和声",
                  "录音", "吉他", "贝斯", "鼓", "出品", "发行", "词", "曲",
                  "OP", "SP", "Lyricist", "Composer", "Arranger", "Producer"]
        credits = "\n".join("[00:00]" + label.swapcase() + "：Credit" for label in labels)
        text = credits + "\n[00:01.25]Real lyric\n[00:02]My Composer: a lyric\n[00:03]Producer of dreams"
        with self.retry_environment([
            response(None), response([]), response(netease_search(netease_song())),
            response({"code": 200, "lrc": {"lyric": text}}),
        ]) as env:
            cache, state, clock, requests = env
            self.assertEqual(self.lyrics.lookup_lyrics(track(), cache).lines, [
                (1250, "Real lyric"), (2000, "My Composer: a lyric"), (3000, "Producer of dreams"),
            ])

    def test_netease_instrumental_empty_and_credit_only_are_definitive_negatives(self):
        payloads = [
            {"code": 200, "nolyric": True, "lrc": {"lyric": "[00:01]Not lyrics"}},
            {"code": 200, "uncollected": True},
            {"code": 200, "lrc": {"lyric": "[00:00]纯音乐，请欣赏"}},
            {"code": 200, "lrc": {"lyric": "[00:00]作词 : Credit\n[00:01]"}},
            {"code": 200, "lrc": {"lyric": ""}},
        ]
        for payload in payloads:
            with self.subTest(payload=payload), self.retry_environment([
                response(None), response([]), response(netease_search(netease_song())),
                response(payload),
            ]) as env:
                cache, state, clock, requests = env
                result = self.lyrics.lookup_lyrics(track(), cache)
                self.assertIsNone(result.lines)
                self.assertIsNone(result.retry_at)
                self.assertTrue(cache.read(track(), NOW + DAY - 1).fresh)
                self.assertFalse(cache.read(track(), NOW + DAY).fresh)

    def test_netease_rescues_lrclib_transient_failure(self):
        for failure in (
            URLError("offline"),
            HTTPError("https://lrclib.net/api/get", 503, "Unavailable", {"Retry-After": "90"}, None),
        ):
            with self.subTest(failure=failure), self.retry_environment([
                failure, response(netease_search(netease_song())),
                response({"code": 200, "lrc": {"lyric": "[00:01]Rescued"}}),
            ]) as env:
                cache, state, clock, requests = env
                result = self.lyrics.lookup_lyrics(track(), cache)
                self.assertEqual(result.lines, [(1000, "Rescued")])
                self.assertIsNone(result.retry_at)
                self.assertTrue(cache.read(track(), NOW + 30 * DAY - 1).fresh)
                self.assertEqual(requests.call_count, 3)

    def test_netease_miss_after_lrclib_transient_does_not_negative_cache(self):
        with self.retry_environment([URLError("offline"), response(netease_search())]) as env:
            cache, state, clock, requests = env
            key = state.update_track(track())
            self.lookup_into_state(cache, state, key, track())
            self.assertIsNone(cache.read(track(), NOW))
            self.assertIsNone(state.next_lookup(114.999))
            clock[0] = 120.0
            self.assertEqual(state.next_lookup(clock[0]), (key, track()))
            self.assertEqual(requests.call_count, 2)

    def test_netease_transient_after_lrclib_negative_does_not_negative_cache(self):
        with self.retry_environment([response(None), response([]), URLError("offline")]) as env:
            cache, state, clock, requests = env
            result = self.lyrics.lookup_lyrics(track(), cache)
            self.assertIsNone(result.lines)
            self.assertIsNotNone(result.retry_at)
            self.assertIsNone(cache.read(track(), NOW))
            self.assertEqual(requests.call_count, 3)

    def test_netease_and_lrclib_definitive_misses_cache_negative_for_one_day(self):
        with self.retry_environment([response(None), response([]), response(netease_search())]) as env:
            cache, state, clock, requests = env
            result = self.lyrics.lookup_lyrics(track(), cache)
            self.assertIsNone(result.lines)
            self.assertIsNone(result.retry_at)
            self.assertTrue(cache.read(track(), NOW + DAY - 1).fresh)
            self.assertFalse(cache.read(track(), NOW + DAY).fresh)
            self.assertEqual(requests.call_count, 3)

    def test_lookup_waits_for_stable_key_and_fallback_changes_immediately(self):
        final = track(title="Hold Me Down", artist="Daniel Caesar", length=234)
        with self.retry_environment([
            response(candidate(title="Hold Me Down", artist="Daniel Caesar", duration=234)),
        ]) as env:
            cache, state, clock, requests = env
            old_key = state.update_track(track())
            state.accept_lookup(old_key, [(1000, "Old lyric")])
            submissions = []
            changes = [
                (100.0, track(length=234), "Firasat — Marcell"),
                (100.001, track(title="Hold Me Down", artist="wave to earth", length=234),
                 "Hold Me Down — wave to earth"),
                (100.003, final, "Hold Me Down — Daniel Caesar"),
            ]
            with mock.patch.object(cache, "read", wraps=cache.read) as reads:
                for now, current, fallback in changes:
                    clock[0] = now
                    key = state.update_track(current)
                    self.assertEqual(state.output(1000), {"text": fallback, "synced": False})
                    due = state.next_lookup(now)
                    if due is not None:
                        submissions.append(due)
                clock[0] = 101.002
                state.update_track(final)
                self.assertIsNone(state.next_lookup(clock[0]))
                self.assertEqual(submissions, [])
                self.assertEqual(reads.call_count, 0)
                self.assertEqual(requests.call_count, 0)
                clock[0] = 101.003
                due = state.next_lookup(clock[0])
                self.assertEqual(due, (key, final))
                submissions.append(due)
                self.lookup_into_state(cache, state, *due)
                self.assertIsNone(state.next_lookup(10000))
                self.assertEqual(submissions, [(key, final)])
                self.assertEqual(reads.call_count, 1)
                self.assertEqual(requests.call_count, 1)
                self.assertEqual(state.output(1000), {"text": "A line", "synced": True})

    def test_transient_retry_recovers_same_track_after_minimum_delay(self):
        with self.retry_environment([
            URLError("offline"), response(netease_search()), response(candidate()),
        ]) as env:
            cache, state, clock, requests = env
            current = track()
            key = state.update_track(current)
            self.lookup_into_state(cache, state, key, current)
            self.assertFalse(state.output(1000)["synced"])
            self.assertIsNone(cache.read(current, NOW))
            clock[0] = 114.999
            self.assertIsNone(state.next_lookup(clock[0]))
            self.assertEqual(requests.call_count, 2)
            clock[0] = 115.201
            self.assertEqual(state.next_lookup(clock[0]), (key, current))
            self.assertIsNone(state.next_lookup(clock[0]))
            self.lookup_into_state(cache, state, key, current)
            self.assertEqual(state.output(1000), {"text": "A line", "synced": True})
            self.assertEqual(requests.call_count, 3)
            self.assertIsNone(state.next_lookup(10000))

    def test_transient_retry_stops_after_three_increasing_delays(self):
        replies = [item for _ in range(4) for item in (URLError("offline"), response(netease_search()))]
        with self.retry_environment(replies) as env:
            cache, state, clock, requests = env
            current = track()
            key = state.update_track(current)
            self.lookup_into_state(cache, state, key, current)
            for due in (115.25, 145.5, 205.75):
                clock[0] = due - 0.251
                self.assertIsNone(state.next_lookup(clock[0]))
                clock[0] = due
                self.assertEqual(state.next_lookup(clock[0]), (key, current))
                self.lookup_into_state(cache, state, key, current)
            self.assertIsNone(state.next_lookup(10000))
            self.assertEqual(requests.call_count, 8)
            self.assertFalse(state.output(1000)["synced"])

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

    def test_track_change_cancels_retry_and_rejects_late_failure(self):
        with self.retry_environment([URLError("offline"), response(netease_search())]) as env:
            cache, state, clock, requests = env
            old = track()
            key = state.update_track(old)
            result = self.lyrics.lookup_lyrics(old, cache)
            state.accept_lookup(key, result.lines, result.retry_at)
            new_key = state.update_track(track(title="New song"))
            state.accept_lookup(new_key, [(1000, "New lyric")])
            state.accept_lookup(key, result.lines, result.retry_at)
            self.assertIsNone(state.next_lookup(10000))
            self.assertEqual(state.output(1000), {"text": "New lyric", "synced": True})
            self.assertEqual(requests.call_count, 2)

    def test_retry_waits_for_cooldown_and_keeps_stale_positive_visible(self):
        for status in (429, 503):
            with self.subTest(status=status), self.retry_environment([
                HTTPError("https://lrclib.net/api/get", status, "Unavailable",
                          {"Retry-After": "90"}, None),
                response(netease_search()),
                response(candidate(synced="[00:01]Refreshed")),
            ]) as env:
                cache, state, clock, requests = env
                current = track()
                cache.write(current, [(1000, "Stale lyric")], NOW - 31 * DAY)
                key = state.update_track(current)
                self.lookup_into_state(cache, state, key, current)
                self.assertEqual(state.output(1000), {"text": "Stale lyric", "synced": True})
                clock[0] = 189.999
                self.assertIsNone(state.next_lookup(clock[0]))
                self.assertEqual(requests.call_count, 2)
                clock[0] = 190.0
                self.assertEqual(state.next_lookup(clock[0]), (key, current))
                self.lookup_into_state(cache, state, key, current)
                self.assertEqual(state.output(1000), {"text": "Refreshed", "synced": True})
                self.assertEqual(requests.call_count, 3)

    def test_retry_after_is_honored_for_other_transient_http_statuses(self):
        for status in (408, 500, 502, 504):
            with self.subTest(status=status), self.retry_environment([
                HTTPError("https://lrclib.net/api/get", status, "Unavailable",
                          {"Retry-After": "90"}, None),
                response(netease_search()),
                response(candidate()),
            ]) as env:
                cache, state, clock, requests = env
                current = track()
                key = state.update_track(current)
                self.lookup_into_state(cache, state, key, current)
                for now in (115.0, 189.999):
                    clock[0] = now
                    self.assertIsNone(state.next_lookup(clock[0]))
                self.assertEqual(requests.call_count, 2)
                clock[0] = 190.0
                self.assertEqual(state.next_lookup(clock[0]), (key, current))
                self.lookup_into_state(cache, state, key, current)
                self.assertEqual(state.output(1000), {"text": "A line", "synced": True})
                self.assertEqual(requests.call_count, 3)

    def test_active_cooldown_schedules_retry_without_network_request(self):
        with self.retry_environment([response(netease_search()), response(candidate())]) as env:
            cache, state, clock, requests = env
            self.lyrics._cooldowns["lrclib"] = 180.0
            current = track()
            key = state.update_track(current)
            self.lookup_into_state(cache, state, key, current)
            self.assertEqual(requests.call_count, 1)
            clock[0] = 179.999
            self.assertIsNone(state.next_lookup(clock[0]))
            clock[0] = 180.0
            self.assertEqual(state.next_lookup(clock[0]), (key, current))
            self.lookup_into_state(cache, state, key, current)
            self.assertEqual(state.output(1000), {"text": "A line", "synced": True})
            self.assertEqual(requests.call_count, 2)

    def test_completed_old_lookup_never_paints_after_new_track(self):
        state = self.lyrics.LyricsState()
        old_key = state.update_track(track())
        state.accept_lookup(old_key, [(1000, "Old lyric")])
        self.assertEqual(state.output(1000), {"text": "Old lyric", "synced": True})
        new_key = state.update_track(track(title="New song"))
        self.assertEqual(state.output(1000), {"text": "New song — Marcell", "synced": False})
        state.accept_lookup(old_key, [(1000, "Late old lyric")])
        self.assertEqual(state.output(1000), {"text": "New song — Marcell", "synced": False})
        state.accept_lookup(new_key, [(2000, "New lyric"), (3000, "")])
        self.assertEqual(state.output(1999), {"text": "New song — Marcell", "synced": False})
        self.assertEqual(state.output(2000), {"text": "New lyric", "synced": True})
        self.assertEqual(state.output(3000), {"text": "New song — Marcell", "synced": False})

    def test_lookup_identity_includes_player_artist_and_duration(self):
        for other in [track(player="other"), track(artist="Other"), track(length=249)]:
            with self.subTest(other=other):
                state = self.lyrics.LyricsState()
                key = state.update_track(track())
                state.update_track(other)
                state.accept_lookup(key, [(0, "Wrong track")])
                self.assertFalse(state.output(1000)["synced"])
                self.assertNotEqual(state.output(1000)["text"], "Wrong track")

    def test_fallback_is_single_line_and_none_clears_lyrics(self):
        state = self.lyrics.LyricsState()
        state.update_track(track(title="  A\n song ", artist=" Artist\tName "))
        self.assertEqual(state.output(0), {"text": "A song — Artist Name", "synced": False})
        state.update_track(track(title="Title only", artist=""))
        self.assertEqual(state.output(0), {"text": "Title only", "synced": False})
        key = state.update_track(track())
        state.accept_lookup(key, [(0, "Playing")])
        state.update_track({"state": "none"})
        state.accept_lookup(key, [(0, "Late")])
        self.assertEqual(state.output(0), {"text": "", "synced": False})

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
                mock.patch.dict(self.lyrics.os.environ, {"XDG_CONFIG_HOME": config}), \
                mock.patch.object(self.lyrics.subprocess, "run", side_effect=run), \
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
        result = self.lyrics.lookup_lyrics(current, env.cache)
        env.state.accept_lookup(key, *result)
        return result

    def test_module_loads_without_ytmusicapi(self):
        with mock.patch.dict(sys.modules, {"ytmusicapi": None}):
            spec = importlib.util.spec_from_file_location("island_lyrics_no_ytm", SCRIPT)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
        self.assertTrue(callable(module.lookup_lyrics))

    def test_ytm_timed_lyrics_are_first_and_skip_other_sources(self):
        with self.ytm_environment(ytmusicapi=fake_ytmusicapi(timed=YTM_TIMED)) as env:
            current = ytm_track()
            self.ytm_lookup(env, current)
            self.assertEqual(env.state.output(9199), {"text": "Sun Shower — The Poles", "synced": False})
            self.assertEqual(env.state.output(9200), {"text": "I was a liar", "synced": True})
            self.assertEqual(env.state.output(11000), {"text": "I gave in to the fire", "synced": True})
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
            self.assertEqual(env.state.output(1000), {"text": "From LRCLIB", "synced": True})
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
            self.assertEqual(env.state.output(1000), {"text": "From NetEase", "synced": True})
            self.assertEqual(env.requests.call_count, 4)

    def test_ytm_plain_is_unsynced_estimated_by_position_and_negative_cached_for_a_day(self):
        plain = ["비가 와요", "기다린 만큼 흘러 넘치게", "오, 오오오오", "아직도 넌 끝이 없고"]
        with self.ytm_environment(ALL_MISSES) as env:
            current = ytm_track(length=240)
            result = self.ytm_lookup(env, current)
            self.assertIsNone(result.lines)
            self.assertIsNone(result.retry_at)
            self.assertEqual(env.requests.call_count, 3)
            self.assertEqual(env.state.output(None), {"text": "Sun Shower — The Poles", "synced": False})
            for position, index in [(0, 0), (59999, 0), (60000, 1), (179999, 2),
                                    (180000, 3), (239999, 3), (500000, 3)]:
                with self.subTest(position=position):
                    self.assertEqual(env.state.output(position), {"text": plain[index], "synced": False})
            entry = env.cache.read(current, NOW + DAY - 1)
            self.assertTrue(entry.fresh)
            self.assertIsNone(entry.lines)
            self.assertEqual(entry.plain, plain)
            self.assertFalse(env.cache.read(current, NOW + DAY).fresh)
            self.assertEqual(env.stderr.getvalue(), "")

    def test_plain_lyrics_from_timestamped_request_need_no_second_request(self):
        with self.ytm_environment(ALL_MISSES, ytmusicapi=fake_ytmusicapi(timed=YTM_PLAIN)) as env:
            self.ytm_lookup(env, ytm_track(length=240))
            self.assertEqual(env.state.output(0), {"text": "비가 와요", "synced": False})
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
            self.assertEqual(env.state.output(0), {"text": "비가 와요", "synced": False})
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
                result = self.lyrics.lookup_lyrics(current, env.cache)
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
                self.assertEqual(env.state.output(0), {"text": "Sun Shower — The Poles", "synced": False})

    def test_track_change_drops_plain_lyrics(self):
        state = self.lyrics.LyricsState()
        old_key = state.update_track(ytm_track(length=240))
        state.accept_lookup(old_key, None, None, ["Old plain"])
        self.assertEqual(state.output(0), {"text": "Old plain", "synced": False})
        state.update_track(ytm_track(title="New song", length=240))
        state.accept_lookup(old_key, None, None, ["Late plain"])
        self.assertEqual(state.output(0), {"text": "New song — The Poles", "synced": False})

    def test_worker_delivers_plain_lyrics(self):
        result = self.lyrics.LookupResult(None, None, ["Plain"])
        with mock.patch.object(self.lyrics, "lookup_lyrics", return_value=result):
            worker = self.lyrics.LookupWorker(cache=None)
            try:
                worker.submit("key", ytm_track())
                for _ in range(200):
                    completed = worker.take_result()
                    if completed is not None:
                        break
                    worker.thread.join(0.01)
                self.assertEqual(completed, ("key", None, None, ["Plain"]))
            finally:
                worker.close()


if __name__ == "__main__":
    unittest.main()
