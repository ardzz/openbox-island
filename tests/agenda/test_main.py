"""The watch loop and collection over fake feeds."""

import datetime as dt
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest import mock
import urllib.error

from .fixtures import FEED, HOME, OFFICE, TZ, at, fake_fetch
from agenda_pkg import main


class WindowTests(unittest.TestCase):
    def test_window_spans_today_and_the_next_cal_days(self):
        start = dt.datetime(2026, 10, 21, tzinfo=TZ)
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop("ISLAND_CAL_DAYS", None)
            self.assertEqual(main.window(at(21, 10), TZ),
                             (start, dt.datetime(2026, 11, 21, tzinfo=TZ)))
        with mock.patch.dict(os.environ, {"ISLAND_CAL_DAYS": "7"}):
            self.assertEqual(main.window(at(21, 10), TZ),
                             (start, dt.datetime(2026, 10, 29, tzinfo=TZ)))
        for bad in ("x", "0", "-3"):
            with self.subTest(days=bad), mock.patch.dict(os.environ, {"ISLAND_CAL_DAYS": bad}):
                self.assertEqual(main.window(at(21, 10), TZ),
                                 (start, dt.datetime(2026, 11, 21, tzinfo=TZ)))
        for big in ("366", "367", "99999999"):
            with self.subTest(days=big), mock.patch.dict(os.environ, {"ISLAND_CAL_DAYS": big}):
                self.assertEqual(main.window(at(21, 10), TZ),
                                 (start, dt.datetime(2027, 10, 23, tzinfo=TZ)))


class CollectTests(unittest.TestCase):
    def test_collect_expands_weekly_series_across_the_default_window(self):
        with tempfile.TemporaryDirectory() as cache:
            timed, _, errors, _ = main.collect([OFFICE], cache, at(21, 10), TZ, lambda url: FEED)
        self.assertEqual(errors, [])
        dates = sorted({dt.datetime.fromtimestamp(event["start"], TZ).date().isoformat()
                        for event in timed if event["title"] == "Weekly Report"})
        self.assertEqual(dates, ["2026-10-22", "2026-10-28", "2026-11-04", "2026-11-11", "2026-11-18"])

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


class SignalTests(unittest.TestCase):
    def test_sigterm_ends_watch_at_once_even_while_it_is_busy(self):
        # The island stops its alert worker with SIGTERM; a watch that outlives it keeps writing agenda.json.
        script = ("import os, signal, time\n"
                  "from agenda_pkg import main\n"
                  "def busy(*args, **kwargs):\n"
                  "    os.kill(os.getpid(), signal.SIGTERM)\n"
                  "    time.sleep(5)\n"
                  "main.watch = busy\n"
                  "main.main(['watch'])\n")
        scripts = Path(__file__).resolve().parents[2] / "eww" / "scripts"
        env = dict(os.environ, PYTHONPATH=str(scripts))
        started = time.monotonic()
        done = subprocess.run([sys.executable, "-c", script], env=env, timeout=10, capture_output=True)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertLess(time.monotonic() - started, 3)
