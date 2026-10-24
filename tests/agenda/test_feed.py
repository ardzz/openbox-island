"""Config lines and permissions; feed fetching with a cached fallback."""

import os
from pathlib import Path
import tempfile
import unittest
import urllib.error

from .fixtures import FEED, OFFICE
from agenda_pkg import config, fetch


class ConfigTests(unittest.TestCase):
    def test_parse_reads_accounts_and_reports_bad_lines_by_number(self):
        accounts, errors = config.parse("# akun\n\nKantor | #4f8cff | Reky@Kantor.co.id | https://a/b.ics\n"
                                        "rusak\nP | biru | x | https://c\nQ | #000000 | | http://d\n"
                                        "Pribadi | #34c759 |  | https://e/f.ics\n")
        self.assertEqual(accounts, [config.Account("Kantor", "#4f8cff", "reky@kantor.co.id", "https://a/b.ics"),
                                    config.Account("Pribadi", "#34c759", "", "https://e/f.ics")])
        self.assertEqual(errors, ["baris 4 config kalender tidak valid", "baris 5 config kalender tidak valid",
                                  "baris 6 config kalender tidak valid"])

    def test_load_flags_files_others_can_read_and_treats_missing_as_empty(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "calendars"
            self.assertEqual(config.load(path), ([], [], False))
            path.write_text("Kantor | #4f8cff | a@b.c | https://a/b.ics\n", encoding="utf-8")
            os.chmod(path, 0o644)
            self.assertTrue(config.load(path)[2])
            os.chmod(path, 0o600)
            self.assertFalse(config.load(path)[2])

    def test_config_path_prefers_the_override_then_xdg_config_home(self):
        self.assertEqual(config.config_path({"ISLAND_CALENDARS": "/x/cal"}), Path("/x/cal"))
        self.assertEqual(config.config_path({"XDG_CONFIG_HOME": "/cfg"}), Path("/cfg/openbox-island/calendars"))


class FetchTests(unittest.TestCase):
    def test_a_good_fetch_is_cached_and_a_later_failure_falls_back_to_it(self):
        with tempfile.TemporaryDirectory() as root:
            self.assertEqual(fetch.refresh(root, OFFICE.url, lambda url: FEED), (FEED, ""))

            def gone(url):
                raise urllib.error.HTTPError(url, 404, "Not Found", {}, None)
            self.assertEqual(fetch.refresh(root, OFFICE.url, gone), (FEED, "HTTP 404"))

    def test_failures_without_a_cache_return_nothing_and_never_mention_the_url(self):
        def offline(url):
            raise urllib.error.URLError(f"cannot reach {url}")
        with tempfile.TemporaryDirectory() as root:
            raw, error = fetch.refresh(root, OFFICE.url, offline)
            self.assertIsNone(raw)
            self.assertEqual(error, "gagal mengambil")
            self.assertNotIn("calendar.example", error)

    def test_responses_that_are_not_calendars_are_rejected(self):
        with self.assertRaisesRegex(fetch.FeedError, "bukan file kalender"):
            fetch.validate(b"<html>login</html>")
        with self.assertRaisesRegex(fetch.FeedError, "lebih dari 5 MB"):
            fetch.validate(b"BEGIN:VCALENDAR" + b"x" * fetch.MAX_BYTES)
        self.assertEqual(fetch.validate(FEED), FEED)

    def test_each_url_has_its_own_cache_file(self):
        self.assertNotEqual(fetch.cache_file("/c", "https://a"), fetch.cache_file("/c", "https://b"))
        self.assertNotIn("https", fetch.cache_file("/c", "https://a").name)
