"""Config lines and permissions; feed fetching with a cached fallback."""

import http.client
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock
import urllib.error

from .fixtures import FEED, OFFICE
from agenda_pkg import config, fetch


class ConfigTests(unittest.TestCase):
    def test_parse_reads_accounts_and_reports_bad_lines_by_number(self):
        accounts, errors = config.parse("# akun\n\nKantor | #4f8cff | Reky@Kantor.co.id | https://a/b.ics\n"
                                        "rusak\nP | biru | x | https://c\nQ | #000000 | | http://d\n"
                                        "Pribadi | #34c759 |  | https://e/f.ics\n"
                                        "R | #000000 | | https://a b\n")
        self.assertEqual(accounts, [config.Account("Kantor", "#4f8cff", "reky@kantor.co.id", "https://a/b.ics"),
                                    config.Account("Pribadi", "#34c759", "", "https://e/f.ics")])
        self.assertEqual(errors, ["baris 4 config kalender tidak valid", "baris 5 config kalender tidak valid",
                                  "baris 6 config kalender tidak valid", "baris 8 config kalender tidak valid"])

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

    def test_protocol_errors_never_expose_the_private_url(self):
        def invalid(url):
            raise http.client.InvalidURL(f"invalid path {url}?token=secret")
        with tempfile.TemporaryDirectory() as root:
            result = fetch.refresh(root, OFFICE.url, invalid)
            self.assertEqual(result, (None, "gagal mengambil"))
            self.assertNotIn("secret", str(result))

    def test_a_cache_root_that_is_a_file_does_not_discard_downloaded_data(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "cache"
            path.write_bytes(b"existing")
            self.assertEqual(fetch.refresh(path, OFFICE.url, lambda url: FEED), (FEED, ""))
            self.assertEqual(path.read_bytes(), b"existing")
            self.assertEqual(list(Path(root).glob("*.tmp")), [])

    def test_failed_replacement_preserves_cache_and_removes_temporary_files(self):
        with tempfile.TemporaryDirectory() as root:
            path = fetch.cache_file(root, OFFICE.url)
            path.write_bytes(b"previous")
            with mock.patch.object(fetch.os, "replace", side_effect=OSError("write failed")):
                self.assertEqual(fetch.refresh(root, OFFICE.url, lambda url: FEED), (FEED, ""))
            self.assertEqual(path.read_bytes(), b"previous")
            self.assertEqual(list(Path(root).glob("*.tmp")), [])

    def test_existing_cache_directory_is_made_private(self):
        with tempfile.TemporaryDirectory() as root:
            os.chmod(root, 0o755)
            self.assertEqual(fetch.refresh(root, OFFICE.url, lambda url: FEED), (FEED, ""))
            self.assertEqual(Path(root).stat().st_mode & 0o777, 0o700)

    def test_failed_permission_change_keeps_download_and_previous_cache(self):
        with tempfile.TemporaryDirectory() as root:
            path = fetch.cache_file(root, OFFICE.url)
            path.write_bytes(b"previous")
            with mock.patch.object(Path, "chmod", side_effect=OSError("chmod failed")):
                self.assertEqual(fetch.refresh(root, OFFICE.url, lambda url: FEED), (FEED, ""))
            self.assertEqual(path.read_bytes(), b"previous")
            self.assertEqual(list(Path(root).glob("*.tmp")), [])

    def test_failed_content_check_preserves_cache_without_exposing_the_exception(self):
        with tempfile.TemporaryDirectory() as root:
            fetch.refresh(root, OFFICE.url, lambda url: FEED)
            check = mock.Mock(side_effect=RuntimeError(OFFICE.url))
            result = fetch.refresh(root, OFFICE.url, lambda url: b"broken", check=check)
            self.assertEqual(result, (FEED, "kalender tidak bisa dibaca"))
            self.assertEqual(fetch.cache_file(root, OFFICE.url).read_bytes(), FEED)
        check.assert_called_once_with(b"broken")
