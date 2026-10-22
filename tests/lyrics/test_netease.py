"""NetEase fallback source."""

from urllib.error import HTTPError, URLError

from .fixtures import LyricsCase, DAY, NOW, track, candidate, response, netease_song, netease_search
from lyrics_pkg.lookup import lookup_lyrics


class NeteaseTests(LyricsCase):
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
                result = lookup_lyrics(current, cache)
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
                result = lookup_lyrics(track(artist="Marcell - Topic"), cache)
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
            self.assertEqual(lookup_lyrics(track(), cache).lines, [
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
                result = lookup_lyrics(track(), cache)
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
                result = lookup_lyrics(track(), cache)
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
            result = lookup_lyrics(track(), cache)
            self.assertIsNone(result.lines)
            self.assertIsNotNone(result.retry_at)
            self.assertIsNone(cache.read(track(), NOW))
            self.assertEqual(requests.call_count, 3)

    def test_netease_and_lrclib_definitive_misses_cache_negative_for_one_day(self):
        with self.retry_environment([response(None), response([]), response(netease_search())]) as env:
            cache, state, clock, requests = env
            result = lookup_lyrics(track(), cache)
            self.assertIsNone(result.lines)
            self.assertIsNone(result.retry_at)
            self.assertTrue(cache.read(track(), NOW + DAY - 1).fresh)
            self.assertFalse(cache.read(track(), NOW + DAY).fresh)
            self.assertEqual(requests.call_count, 3)
