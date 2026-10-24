"""The check command over fake feeds."""

import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from .fixtures import HOME, OFFICE, fake_fetch
from agenda_pkg import main


class CheckTests(unittest.TestCase):
    def test_check_reports_each_account_without_urls_and_fails_on_errors(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "calendars"
            path.write_text(f"Kantor | #4f8cff | reky@kantor.co.id | {OFFICE.url}\n"
                            f"Pribadi | #34c759 | | {HOME.url}\n")
            os.chmod(path, 0o644)
            env = {"ISLAND_CALENDARS": str(path), "XDG_CACHE_HOME": f"{root}/cache", "TZ": "Asia/Jakarta"}
            lines = []
            with mock.patch.dict(os.environ, env), mock.patch.object(main.fetch, "download", fake_fetch), \
                    mock.patch("builtins.print", side_effect=lambda *a, **k: lines.append(" ".join(map(str, a)))):
                status = main.check()
        self.assertEqual(status, 1)
        self.assertTrue(lines[0].startswith("peringatan:"))
        self.assertTrue(lines[1].startswith("Kantor: OK"))
        self.assertEqual(lines[2], "Pribadi: HTTP 401")
        self.assertFalse(any("calendar.example" in line for line in lines))

    def test_check_explains_a_missing_config(self):
        with tempfile.TemporaryDirectory() as root, \
                mock.patch.dict(os.environ, {"ISLAND_CALENDARS": f"{root}/none"}):
            lines = []
            with mock.patch("builtins.print", side_effect=lambda *a, **k: lines.append(a[0])):
                self.assertEqual(main.check(), 1)
        self.assertTrue(lines[0].startswith("config kalender belum ada"))

    def test_check_fails_while_the_config_lists_no_calendars(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "calendars"
            path.write_text("# Kantor | #4f8cff | | https://x\n")
            path.chmod(0o600)
            with mock.patch.dict(os.environ, {"ISLAND_CALENDARS": str(path)}), \
                    mock.patch("builtins.print") as printed:
                self.assertEqual(main.check(), 1)
        printed.assert_called_once_with(f"belum ada kalender di config: {path}")

    def test_check_reports_missing_libraries_for_each_account(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "calendars"
            path.write_text(f"Kantor | #4f8cff | | {OFFICE.url}\n")
            path.chmod(0o600)
            env = {"ISLAND_CALENDARS": str(path), "XDG_CACHE_HOME": f"{root}/cache"}
            with mock.patch.dict(os.environ, env), \
                    mock.patch.dict("sys.modules", {"agenda_pkg.events": None}), \
                    mock.patch("builtins.print") as printed:
                self.assertEqual(main.check(), 1)
        printed.assert_called_once_with("Kantor: python-icalendar belum terpasang")
