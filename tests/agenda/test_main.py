"""The watch loop and check command over fake feeds."""

import json
import os
from pathlib import Path
import tempfile
import threading
import unittest
from unittest import mock
import urllib.error

from .fixtures import FEED, HOME, OFFICE, TZ, at
from agenda_pkg import main


def fake_fetch(url):
    if "pribadi" in url:
        raise urllib.error.HTTPError(url, 401, "Unauthorized", {}, None)
    return FEED


class CollectTests(unittest.TestCase):
    def test_collect_merges_accounts_and_reports_failures_by_name(self):
        with tempfile.TemporaryDirectory() as cache:
            timed, allday, errors, stale = main.collect([OFFICE, HOME], cache, at(21, 10), TZ, fake_fetch)
        self.assertTrue(timed and allday)
        self.assertEqual(errors, ["Pribadi: HTTP 401"])
        self.assertFalse(stale)

    def test_a_failed_refetch_keeps_the_cached_feed_and_marks_it_stale(self):
        with tempfile.TemporaryDirectory() as cache:
            main.collect([OFFICE], cache, at(21, 10), TZ, lambda url: FEED)
            offline = mock.Mock(side_effect=urllib.error.URLError("down"))
            timed, _, errors, stale = main.collect([OFFICE], cache, at(21, 10), TZ, offline)
        self.assertTrue(timed)
        self.assertEqual((errors, stale), (["Kantor: gagal mengambil"], True))

    def test_an_unreadable_feed_is_reported_without_breaking_the_others(self):
        with tempfile.TemporaryDirectory() as cache:
            broken = lambda url: b"BEGIN:VCALENDAR\r\nthis is not ical\r\nEND:VCALENDAR\r\n"
            _, _, errors, _ = main.collect([OFFICE], cache, at(21, 10), TZ, broken)
        self.assertEqual(errors, ["Kantor: kalender tidak bisa dibaca"])

    def test_invalid_refetch_preserves_the_good_cache(self):
        with tempfile.TemporaryDirectory() as cache:
            expected = main.collect([OFFICE], cache, at(21, 10), TZ, lambda url: FEED)
            broken = lambda url: b"BEGIN:VCALENDAR\r\nthis is not ical\r\nEND:VCALENDAR\r\n"
            timed, allday, errors, stale = main.collect([OFFICE], cache, at(21, 10), TZ, broken)
            self.assertEqual(main.fetch.cache_file(cache, OFFICE.url).read_bytes(), FEED)
        self.assertEqual((timed, allday), expected[:2])
        self.assertEqual((errors, stale), (["Kantor: kalender tidak bisa dibaca"], True))


class WatchTests(unittest.TestCase):
    def run_watch(self, root, now, fetcher=None, clock=None, ticks=1,
                  config=f"Kantor | #4f8cff | reky@kantor.co.id | {OFFICE.url}\n"):
        env = {"XDG_RUNTIME_DIR": f"{root}/run", "XDG_CACHE_HOME": f"{root}/cache",
               "ISLAND_CALENDARS": f"{root}/calendars", "TZ": "Asia/Jakarta"}
        Path(env["ISLAND_CALENDARS"]).write_text(config)
        stopped = threading.Event()
        printed = []

        def tick(*args, **kwargs):
            printed.append(args)
            if len(printed) >= ticks:
                stopped.set()

        with mock.patch.dict(os.environ, env), \
                mock.patch.object(main.fetch, "download", fetcher or (lambda url: FEED)), \
                mock.patch("builtins.print", side_effect=tick), mock.patch.object(stopped, "wait"):
            main.watch(clock=clock or (lambda: now), stopped=stopped)
        return json.loads(Path(env["XDG_RUNTIME_DIR"], "eww-island", "agenda.json").read_text()), printed

    def test_watch_publishes_the_agenda_and_prints_a_tick(self):
        with tempfile.TemporaryDirectory() as root:
            document, printed = self.run_watch(root, at(21, 14, 50))
        self.assertTrue(document["ok"])
        self.assertEqual(document["next"]["title"], "Standup")
        self.assertEqual(document["allday"], ["Cuti Bersama", "Konferensi"])
        self.assertEqual(printed, [(at(21, 14, 50),)])

    def test_watch_publishes_a_failure_when_the_libraries_are_missing(self):
        with tempfile.TemporaryDirectory() as root, mock.patch.dict("sys.modules", {"agenda_pkg.events": None}):
            document, _ = self.run_watch(root, at(21, 10))
        self.assertEqual((document["ok"], document["error"]), (False, "python-icalendar belum terpasang"))

    def test_watch_publishes_a_failure_while_the_config_lists_no_calendars(self):
        with tempfile.TemporaryDirectory() as root:
            document, _ = self.run_watch(root, at(21, 10), config="# Kantor | #4f8cff | | https://x\n")
        self.assertEqual((document["ok"], document["error"]), (False, "belum ada kalender di config"))

    def test_watch_renders_with_the_time_after_fetching(self):
        now = [at(21, 14, 59)]

        def fetcher(url):
            now[0] = at(21, 15, 1)
            return FEED

        with tempfile.TemporaryDirectory() as root:
            document, _ = self.run_watch(root, now[0], fetcher, lambda: now[0])
        standup = next(row for row in document["rows"] if row["title"] == "Standup")
        self.assertEqual(standup["state"], "now")

    def test_watch_refetches_after_local_midnight(self):
        tz = TZ
        midnight = int(main.dt.datetime(2026, 10, 22, tzinfo=tz).timestamp())
        now = [midnight - 1]
        fetcher = mock.Mock(return_value=FEED)

        def clock():
            current = now[0]
            now[0] = midnight + 1
            return current

        with tempfile.TemporaryDirectory() as root, \
                mock.patch.dict(os.environ, {"ISLAND_CAL_INTERVAL": "86400"}):
            self.run_watch(root, now[0], fetcher, clock, ticks=2)
        self.assertEqual(fetcher.call_count, 2)

    def test_failed_refresh_keeps_the_last_successful_update_time(self):
        now = [at(21, 9, 55)]
        calls = []

        def fetcher(url):
            calls.append(url)
            if len(calls) > 1:
                raise urllib.error.URLError("offline")
            return FEED

        def clock():
            current = now[0]
            now[0] += 60
            return current

        with tempfile.TemporaryDirectory() as root, \
                mock.patch.dict(os.environ, {"ISLAND_CAL_INTERVAL": "1"}):
            document, _ = self.run_watch(root, now[0], fetcher, clock, ticks=2)
        self.assertEqual(len(calls), 2)
        self.assertEqual(document["updated"], "09:56")
        self.assertTrue(document["stale"])

    def test_local_timezone_preserves_daylight_saving_rules(self):
        with mock.patch.dict(os.environ, {"TZ": "Europe/Berlin"}):
            tz = main.local_tz()
        self.assertEqual(getattr(tz, "key", None), "Europe/Berlin")
        before = main.dt.datetime(2026, 10, 24, 12, tzinfo=tz)
        after = main.dt.datetime(2026, 10, 26, 12, tzinfo=tz)
        self.assertNotEqual(before.utcoffset(), after.utcoffset())


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
