"""LRC parsing and line choice."""

from .fixtures import LyricsCase
from lyrics_pkg.lrc import line_at, parse_lrc


class LrcTests(LyricsCase):
    def test_lrc_fractional_multiple_timestamps_and_metadata(self):
        lines = parse_lrc(
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
                self.assertEqual(line_at(lines, position), expected)

    def test_lrc_positive_offset_advances_line_and_negative_delays_it(self):
        advanced = parse_lrc("[offset:250]\n[00:01.00]Advanced")
        self.assertEqual(advanced, [(750, "Advanced")])
        self.assertIsNone(line_at(advanced, 749))
        self.assertEqual(line_at(advanced, 750), "Advanced")
        delayed = parse_lrc("[00:01.00]Delayed\n[offset:-250]")
        self.assertEqual(delayed, [(1250, "Delayed")])
        self.assertIsNone(line_at(delayed, 1249))
        self.assertEqual(line_at(delayed, 1250), "Delayed")

    def test_lrc_offset_preserves_negative_effective_timestamps(self):
        lines = parse_lrc("[offset:1250]\n[00:01.00]Already active")
        self.assertEqual(lines, [(-250, "Already active")])
        self.assertIsNone(line_at(lines, -251))
        self.assertEqual(line_at(lines, -250), "Already active")
        self.assertEqual(line_at(lines, 0), "Already active")
