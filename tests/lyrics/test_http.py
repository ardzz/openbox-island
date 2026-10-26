"""Request spacing, Retry-After and per-source cooldowns."""

from urllib.error import HTTPError

from .fixtures import LyricsCase, DAY, NOW, track, candidate, response, netease_search
from lyrics_pkg import http as lyrics_http
from lyrics_pkg.http import request_json


class HttpTests(LyricsCase):
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
            self.assertIsNone(request_json("get", {}))
            with self.assertRaises(HTTPError):
                request_json("search/get", {}, source="netease")
            self.assertEqual(request_json("search", {}), [])
            with self.assertRaises(OSError):
                request_json("search/get", {}, source="netease")
            self.assertEqual(len(starts), 3)
            for actual, expected in zip(starts, (100.0, 100.2, 100.4)):
                self.assertAlmostEqual(actual, expected)
            self.assertEqual(requests.call_count, 3)

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
                self.assert_line(state, 1000, "Stale lyric", True)
                clock[0] = 189.999
                self.assertIsNone(state.next_lookup(clock[0]))
                self.assertEqual(requests.call_count, 2)
                clock[0] = 190.0
                self.assertEqual(state.next_lookup(clock[0]), (key, current))
                self.lookup_into_state(cache, state, key, current)
                self.assert_line(state, 1000, "Refreshed", True)
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
                self.assert_line(state, 1000, "A line", True)
                self.assertEqual(requests.call_count, 3)

    def test_active_cooldown_schedules_retry_without_network_request(self):
        with self.retry_environment([response(netease_search()), response(candidate())]) as env:
            cache, state, clock, requests = env
            lyrics_http._cooldowns["lrclib"] = 180.0
            current = track()
            key = state.update_track(current)
            self.lookup_into_state(cache, state, key, current)
            self.assertEqual(requests.call_count, 1)
            clock[0] = 179.999
            self.assertIsNone(state.next_lookup(clock[0]))
            clock[0] = 180.0
            self.assertEqual(state.next_lookup(clock[0]), (key, current))
            self.lookup_into_state(cache, state, key, current)
            self.assert_line(state, 1000, "A line", True)
            self.assertEqual(requests.call_count, 2)
