"""Consumer contracts for the standalone, stdlib-only lyrics listener."""

from contextlib import contextmanager, redirect_stderr
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
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

        with tempfile.TemporaryDirectory() as root, \
                mock.patch.object(self.lyrics, "_next_request", 0.0), \
                mock.patch.object(self.lyrics, "_cooldowns", {"lrclib": 0.0, "netease": 0.0}), \
                mock.patch.object(self.lyrics.time, "monotonic", side_effect=lambda: clock[0]), \
                mock.patch.object(self.lyrics.time, "time", return_value=NOW), \
                mock.patch.object(self.lyrics.time, "sleep", side_effect=advance), \
                mock.patch.object(self.lyrics.urllib.request, "urlopen", side_effect=replies) as requests, \
                redirect_stderr(io.StringIO()):
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


if __name__ == "__main__":
    unittest.main()
