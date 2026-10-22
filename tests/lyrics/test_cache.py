"""On-disk cache freshness, identity and corruption handling."""

import json
from pathlib import Path
import tempfile

from .fixtures import LyricsCase, DAY, NOW, track
from lyrics_pkg.cache import LyricsCache


class CacheTests(LyricsCase):
    def test_positive_cache_freshness_and_stale_lines(self):
        with tempfile.TemporaryDirectory() as root:
            cache = LyricsCache(Path(root))
            cache.write(track(), [(1000, "Cached")], NOW)
            self.assertTrue(cache.read(track(), NOW + 30 * DAY - 1).fresh)
            stale = cache.read(track(), NOW + 30 * DAY + 1)
            self.assertFalse(stale.fresh)
            self.assertEqual(stale.lines, [(1000, "Cached")])

    def test_negative_cache_expires_after_one_day(self):
        with tempfile.TemporaryDirectory() as root:
            cache = LyricsCache(Path(root))
            cache.write(track(), None, NOW)
            self.assertTrue(cache.read(track(), NOW + DAY - 1).fresh)
            self.assertIsNone(cache.read(track(), NOW + DAY - 1).lines)
            self.assertFalse(cache.read(track(), NOW + DAY + 1).fresh)

    def test_old_parsed_cache_version_is_a_miss(self):
        with tempfile.TemporaryDirectory() as root:
            cache = LyricsCache(Path(root))
            cache.write(track(), [(1250, "Old offset direction")], NOW)
            files = list(Path(root).glob("*.json"))
            self.assertEqual(len(files), 1)
            data = json.loads(files[0].read_text(encoding="utf-8"))
            data["version"] = 1
            files[0].write_text(json.dumps(data), encoding="utf-8")
            self.assertIsNone(cache.read(track(), NOW))

    def test_cache_identity_uses_clean_metadata_and_duration_not_player(self):
        with tempfile.TemporaryDirectory() as root:
            cache = LyricsCache(Path(root))
            cache.write(track(), [(1000, "Cached")], NOW)
            same = track(title="Firasat [Official Audio]", artist="Marcell - Topic", player="other")
            self.assertEqual(cache.read(same, NOW).lines, [(1000, "Cached")])
            for other in [track(title="Firasat (Live)"), track(artist="Other"), track(length=249)]:
                self.assertIsNone(cache.read(other, NOW))

    def test_corrupt_or_mismatched_cache_is_a_miss(self):
        with tempfile.TemporaryDirectory() as root:
            cache = LyricsCache(Path(root))
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
