"""Strict LRCLIB and NetEase candidate matching."""

from .fixtures import LyricsCase, track, candidate, netease_song
from lyrics_pkg.match import choose_candidate, choose_netease_candidate


class MatchTests(LyricsCase):
    def test_match_chooses_closest_strict_synced_candidate(self):
        choices = [candidate(duration=246, synced="[00:01]Far"),
                   candidate(duration=248.5, synced="[00:01]Closest"),
                   candidate(duration=249, synced="[00:01]Near")]
        selected = choose_candidate(track(), choices)
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
                self.assertIsNone(choose_candidate(track(), [item]))
        for duration in [246, 250]:
            with self.subTest(boundary=duration):
                self.assertIsNotNone(choose_candidate(track(), [candidate(duration=duration)]))
        for duration in [None, 0, True, float("nan")]:
            with self.subTest(track_duration=duration):
                self.assertIsNone(choose_candidate(track(length=duration), [candidate()]))

    def test_matching_accepts_clean_topic_and_promo_without_losing_version(self):
        selected = choose_candidate(
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
                    lrclib = choose_candidate(
                        current, [candidate(artist=candidate_artist, duration=249.5)])
                    netease = choose_netease_candidate(
                        current, [netease_song(artist=candidate_artist, duration=249500)])
                    self.assertEqual(lrclib is not None, accepted)
                    self.assertEqual(netease is not None, accepted)
