"""Title and artist normalization."""

from .fixtures import LyricsCase
from lyrics_pkg.text import normalize_artist, normalize_title


class TextTests(LyricsCase):
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
                self.assertEqual(normalize_title(value), expected)
        self.assertEqual(normalize_artist("  Marcell - Topic  "), "marcell")
        self.assertEqual(normalize_artist("Topic - Marcell"), "topic - marcell")
