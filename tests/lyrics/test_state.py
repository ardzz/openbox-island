"""Per-track state: stable keys, retries and the emitted line."""

from unittest import mock
from urllib.error import URLError

from .fixtures import LyricsCase, NOW, track, candidate, response, netease_search
from .ytm_fixtures import ytm_track
from lyrics_pkg.lookup import lookup_lyrics
from lyrics_pkg.state import LyricsState


class StateTests(LyricsCase):
    def test_output_synced_timeline_boundaries(self):
        state = LyricsState()
        key = state.update_track(track())
        timeline = [(1000, "First"), (2000, "Second"), (2000, "Same stamp"), (4000, "Last")]
        state.accept_lookup(key, timeline)
        for position, index in [(None, -1), (999, -1), (1000, 0), (1999, 0),
                                (2000, 2), (3999, 2), (4000, 3), (99999, 3)]:
            with self.subTest(position=position):
                output = state.output(position)
                self.assertEqual(output["lines"], [{"t": t, "text": text} for t, text in timeline])
                self.assertEqual(output["index"], index)
                self.assertEqual(output["text"], timeline[index][1] if index >= 0 else "Firasat — Marcell")

    def test_output_plain_timeline_estimate(self):
        state = LyricsState()
        key = state.update_track(track(length=240))
        state.accept_lookup(key, None, plain=["First", "Second", "Third", "Last"])
        for position, index in [(None, -1), (-10, 0), (0, 0), (59999, 0),
                                (60000, 1), (180000, 3), (999999, 3)]:
            with self.subTest(position=position):
                output = state.output(position)
                self.assertEqual(output["lines"], [{"t": -1, "text": text}
                                                  for text in state.plain])
                self.assertEqual(output["index"], index)
                self.assertFalse(output["synced"])

    def test_output_empty_timeline(self):
        state = LyricsState()
        self.assertEqual(state.output(0), {"text": "", "synced": False, "lines": [], "index": -1,
                                          "for_player": "", "for_title": "", "for_artist": "", "for_length": 0})
        state.update_track(track())
        self.assertEqual(state.output(0), {"text": "Firasat — Marcell", "synced": False,
                                          "lines": [], "index": -1,
                                          "for_player": "fixture", "for_title": "Firasat",
                                          "for_artist": "Marcell", "for_length": 248})

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
                    self.assert_line(state, 1000, fallback, False)
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
                self.assert_line(state, 1000, "A line", True)

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
            self.assert_line(state, 1000, "A line", True)
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

    def test_track_change_cancels_retry_and_rejects_late_failure(self):
        with self.retry_environment([URLError("offline"), response(netease_search())]) as env:
            cache, state, clock, requests = env
            old = track()
            key = state.update_track(old)
            result = lookup_lyrics(old, cache)
            state.accept_lookup(key, result.lines, result.retry_at)
            new_key = state.update_track(track(title="New song"))
            state.accept_lookup(new_key, [(1000, "New lyric")])
            state.accept_lookup(key, result.lines, result.retry_at)
            self.assertIsNone(state.next_lookup(10000))
            self.assert_line(state, 1000, "New lyric", True)
            self.assertEqual(requests.call_count, 2)

    def test_completed_old_lookup_never_paints_after_new_track(self):
        state = LyricsState()
        old_key = state.update_track(track())
        state.accept_lookup(old_key, [(1000, "Old lyric")])
        self.assert_line(state, 1000, "Old lyric", True)
        new_key = state.update_track(track(title="New song"))
        self.assert_line(state, 1000, "New song — Marcell", False)
        state.accept_lookup(old_key, [(1000, "Late old lyric")])
        self.assert_line(state, 1000, "New song — Marcell", False)
        state.accept_lookup(new_key, [(2000, "New lyric"), (3000, "")])
        self.assert_line(state, 1999, "New song — Marcell", False)
        self.assert_line(state, 2000, "New lyric", True)
        self.assert_line(state, 3000, "New song — Marcell", False)

    def test_lookup_identity_includes_player_artist_and_duration(self):
        for other in [track(player="other"), track(artist="Other"), track(length=249)]:
            with self.subTest(other=other):
                state = LyricsState()
                key = state.update_track(track())
                state.update_track(other)
                state.accept_lookup(key, [(0, "Wrong track")])
                self.assertFalse(state.output(1000)["synced"])
                self.assertNotEqual(state.output(1000)["text"], "Wrong track")

    def test_output_carries_exact_track_identity_and_clears_when_inactive(self):
        state = LyricsState()
        for current in [None, track(player="spotify", title="  A\n song "),
                        track(player="other", title="New song"),
                        track(player="other", title="New song", artist="Other"),
                        track(player="other", title="New song", artist="Other", length=249),
                        {"state": "none"}]:
            if current is not None:
                state.update_track(current)
            output = state.output(0)
            active = current is not None and current.get("state") in ("playing", "paused")
            self.assertEqual(output["for_player"], current["player"] if active else "")
            self.assertEqual(output["for_title"], current["title"] if active else "")
            self.assertEqual(output["for_artist"], current["artist"] if active else "")
            self.assertEqual(output["for_length"], current["length"] if active else 0)

    def test_fallback_is_single_line_and_none_clears_lyrics(self):
        state = LyricsState()
        state.update_track(track(title="  A\n song ", artist=" Artist\tName "))
        self.assert_line(state, 0, "A song — Artist Name", False)
        state.update_track(track(title="Title only", artist=""))
        self.assert_line(state, 0, "Title only", False)
        key = state.update_track(track())
        state.accept_lookup(key, [(0, "Playing")])
        state.update_track({"state": "none"})
        state.accept_lookup(key, [(0, "Late")])
        self.assert_line(state, 0, "", False)

    def test_track_change_drops_plain_lyrics(self):
        state = LyricsState()
        old_key = state.update_track(ytm_track(length=240))
        state.accept_lookup(old_key, None, None, ["Old plain"])
        self.assert_line(state, 0, "Old plain", False)
        state.update_track(ytm_track(title="New song", length=240))
        state.accept_lookup(old_key, None, None, ["Late plain"])
        self.assert_line(state, 0, "New song — The Poles", False)
