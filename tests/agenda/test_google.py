"""Google Calendar accounts: config, auth, paging, collect and check."""

import datetime as dt
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from .fixtures import TZ, at
from .google_fixtures import ACCOUNT, CLIENT, fake_request, invalid_grant, item, write_env
from agenda_pkg import config, fetch, google, main


class ConfigTests(unittest.TestCase):
    def test_google_calendar_id_and_config_accepts_it(self):
        accounts, errors = config.parse(
            "Kantor | #4f8cff | reky@kantor.co.id | google:primary\n"
            "Tim | #34c759 | | google:abc123@group.calendar.google.com\n"
            "Server | #000000 | | google:has space\n")
        self.assertEqual(errors, ["baris 3 config kalender tidak valid"])
        self.assertEqual([a.url for a in accounts],
                         ["google:primary", "google:abc123@group.calendar.google.com"])
        self.assertEqual(google.calendar_id(accounts[0]), "primary")
        self.assertEqual(google.calendar_id(accounts[1]),
                         "abc123@group.calendar.google.com")
        ical = config.Account("X", "#000000", "", "https://a/b.ics")
        self.assertIsNone(google.calendar_id(ical))


class HelperTests(unittest.TestCase):
    def test_paths_follow_the_calendars_config(self):
        env = {"ISLAND_CALENDARS": "/tmp/x/dir/calendars"}
        with mock.patch.dict(os.environ, env):
            self.assertEqual(google.client_path(), Path("/tmp/x/dir/google-client.json"))
            self.assertEqual(google.tokens_path(), Path("/tmp/x/dir/google-tokens.json"))

    def test_load_client(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "google-client.json"
            path.write_text(json.dumps(
                {"installed": {"client_id": "id1", "client_secret": "s3cr3t"}}))
            self.assertEqual(google.load_client(path),
                             ("id1", "s3cr3t", "https://oauth2.googleapis.com/token"))
            path.write_text(json.dumps(CLIENT))
            self.assertEqual(google.load_client(path),
                             ("cid", "raise-this-secret", "https://tokens.example/token"))
            with self.assertRaisesRegex(fetch.FeedError,
                                        "^google-client\\.json belum ada$"):
                google.load_client(Path(root) / "nope.json")
            path.write_text("{ not json")
            with self.assertRaisesRegex(fetch.FeedError,
                                        "^google-client\\.json tidak valid$"):
                google.load_client(path)
            path.write_text(json.dumps({"installed": {"client_id": "only"}}))
            with self.assertRaisesRegex(fetch.FeedError,
                                        "^google-client\\.json tidak valid$"):
                google.load_client(path)

    def test_load_tokens_missing_or_invalid_is_empty(self):
        with tempfile.TemporaryDirectory() as root:
            self.assertEqual(google.load_tokens(Path(root) / "none.json"), {})
            path = Path(root) / "google-tokens.json"
            path.write_text("bukan json")
            self.assertEqual(google.load_tokens(path), {})
            path.write_text(json.dumps({"Kantor": "refresh-1", "Lain": "refresh-2"}))
            self.assertEqual(google.load_tokens(path),
                             {"Kantor": "refresh-1", "Lain": "refresh-2"})

    def test_access_token(self):
        client = ("cid", "secret-value", "https://tokens.example/token")
        tokens = {"Kantor": "refresh-token-1"}
        with mock.patch.object(google, "request",
                               return_value={"access_token": "acc"}) as req, \
                mock.patch.object(google, "load_tokens", return_value={}):
            with self.assertRaisesRegex(
                    fetch.FeedError, r"^belum login \(agenda login Kantor\)$"):
                google.access_token(ACCOUNT, client)
            req.assert_not_called()
        with mock.patch.object(google, "request",
                               return_value={"access_token": "acc"}) as req, \
                mock.patch.object(google, "load_tokens", return_value=tokens):
            self.assertEqual(google.access_token(ACCOUNT, client), "acc")
            self.assertEqual(req.call_args[0][0], "https://tokens.example/token")
            data = req.call_args.kwargs.get("data") or req.call_args[0][1]
            self.assertEqual(data, {"client_id": "cid",
                                    "client_secret": "secret-value",
                                    "grant_type": "refresh_token",
                                    "refresh_token": "refresh-token-1"})
        with mock.patch.object(google, "request", side_effect=invalid_grant), \
                mock.patch.object(google, "load_tokens", return_value=tokens):
            with self.assertRaisesRegex(
                    fetch.FeedError, r"^login ulang \(agenda login Kantor\)$"):
                google.access_token(ACCOUNT, client)

    def test_list_events_paginates_and_sends_expected_request(self):
        calls = []

        def fake(url, data=None, headers=None):
            calls.append((url, data, headers))
            if len(calls) == 1:
                return {"items": [item(id="a", summary="Satu")],
                        "nextPageToken": "page-2"}
            return {"items": [item(id="b", iCalUID="b@google.com", summary="Dua")]}

        start = dt.datetime(2026, 10, 21, tzinfo=TZ)
        with mock.patch.object(google, "request", side_effect=fake):
            items = google.list_events("akses-token",
                                       "abc123@group.calendar.google.com",
                                       start, start + dt.timedelta(days=31))
        self.assertEqual([entry["summary"] for entry in items], ["Satu", "Dua"])
        self.assertEqual(len(calls), 2)
        url1, data1, headers1 = calls[0]
        self.assertIsNone(data1)
        self.assertEqual(headers1.get("Authorization"), "Bearer akses-token")
        self.assertIn("/calendars/abc123%40group.calendar.google.com/events", url1)
        for part in ("singleEvents=true", "orderBy=startTime", "maxResults=2500",
                     "timeMin=", "timeMax=", "eventTypes=default",
                     "eventTypes=focusTime", "eventTypes=outOfOffice",
                     "eventTypes=fromGmail"):
            self.assertIn(part, url1)
        self.assertIn("pageToken=page-2", calls[1][0])

    def test_list_events_stops_after_ten_pages(self):
        page = {"items": [item()], "nextPageToken": "next"}
        start = dt.datetime(2026, 10, 21, tzinfo=TZ)
        with mock.patch.object(google, "request", return_value=page) as req:
            items = google.list_events("tok", "primary", start,
                                       start + dt.timedelta(days=1))
        self.assertEqual((req.call_count, len(items)), (10, 10))


class CollectTests(unittest.TestCase):
    def collect(self, cache):
        return main.collect([ACCOUNT], cache, at(21, 7), TZ)

    def test_collect_returns_rows_from_google_events(self):
        payload = [item(summary="Standup Pagi",
                        hangoutLink="https://meet.google.com/abc-defg-hij"),
                   item(id="ad", iCalUID="ad@google.com", summary="Cuti Bersama",
                        start={"date": "2026-10-21"}, end={"date": "2026-10-22"})]
        with tempfile.TemporaryDirectory() as root:
            env = write_env(root, tokens={"Kantor": "refresh-token-1"})
            fake = fake_request([{"items": payload}])
            with mock.patch.dict(os.environ, env), \
                    mock.patch.object(google, "request", fake):
                timed, allday, errors, stale = self.collect(str(Path(root) / "cache"))
        self.assertEqual(errors, [])
        self.assertFalse(stale)
        self.assertEqual(len(timed), 1)
        row = timed[0]
        self.assertEqual((row["title"], row["start"], row["end"], row["join"],
                          row["account"]),
                         ("Standup Pagi", at(21, 8), at(21, 8, 30),
                          "https://meet.google.com/abc-defg-hij", "Kantor"))
        self.assertEqual(allday, [{"title": "Cuti Bersama", "account": "Kantor",
                                   "color": "#4f8cff", "first": "2026-10-21",
                                   "last": "2026-10-22"}])
        self.assertEqual(fake.seen[0][1]["refresh_token"], "refresh-token-1")
        self.assertEqual(fake.seen[1][2].get("Authorization"),
                         "Bearer akses-rahasia")
        self.assertIn("primary", fake.seen[1][0])

    def test_two_google_accounts_on_primary_use_separate_caches(self):
        other = config.Account("Lain", "#34c759", "", "google:primary")
        with tempfile.TemporaryDirectory() as root:
            env = write_env(root, tokens={"Kantor": "refresh-1", "Lain": "refresh-2"})
            fake = fake_request([
                {"items": [item(summary="Punya Kantor")]},
                {"items": [item(id="lain1", iCalUID="lain@google.com",
                                summary="Punya Lain")]}])
            cache = str(Path(root) / "cache")
            with mock.patch.dict(os.environ, env), \
                    mock.patch.object(google, "request", fake):
                timed, _, errors, _ = main.collect([ACCOUNT, other], cache,
                                                   at(21, 7), TZ)
            self.assertEqual(errors, [])
            self.assertEqual({row["title"] for row in timed},
                             {"Punya Kantor", "Punya Lain"})
            self.assertEqual(len(list((Path(root) / "cache").rglob("*.ics"))), 2)

    def test_missing_client_missing_login_and_invalid_grant_keep_stale_rows(self):
        good = {"items": [item(summary="Tetap Ada")]}
        with tempfile.TemporaryDirectory() as root:
            cache = str(Path(root) / "cache")
            env = write_env(root, tokens={"Kantor": "refresh-token-1"})
            with mock.patch.dict(os.environ, env), \
                    mock.patch.object(google, "request", fake_request([good])):
                first, _, errors, _ = self.collect(cache)
            self.assertEqual((errors, [row["title"] for row in first]),
                             ([], ["Tetap Ada"]))
            (Path(root) / "google-client.json").unlink()
            with mock.patch.dict(os.environ, env):
                timed, _, errors, stale = self.collect(cache)
            self.assertEqual((errors, stale, [row["title"] for row in timed]),
                             (["Kantor: google-client.json belum ada"], True,
                              ["Tetap Ada"]))
            (Path(root) / "google-client.json").write_text(json.dumps(CLIENT))
            (Path(root) / "google-tokens.json").write_text(json.dumps({"Lain": "x"}))
            with mock.patch.dict(os.environ, env), \
                    mock.patch.object(google, "request", fake_request([good])):
                timed, _, errors, stale = self.collect(cache)
            self.assertEqual((errors, stale, [row["title"] for row in timed]),
                             (["Kantor: belum login (agenda login Kantor)"], True,
                              ["Tetap Ada"]))
            (Path(root) / "google-tokens.json").write_text(
                json.dumps({"Kantor": "refresh-token-1"}))
            with mock.patch.dict(os.environ, env), \
                    mock.patch.object(google, "request", invalid_grant):
                timed, _, errors, stale = self.collect(cache)
            self.assertEqual((errors, stale, [row["title"] for row in timed]),
                             (["Kantor: login ulang (agenda login Kantor)"], True,
                              ["Tetap Ada"]))


class CheckTests(unittest.TestCase):
    def test_check_prints_ok_for_a_google_account_without_secrets(self):
        payload = {"items": [item(summary="Standup"),
                             item(id="ad", iCalUID="ad@google.com", summary="Cuti",
                                  start={"date": "2026-10-21"},
                                  end={"date": "2026-10-22"})]}
        with tempfile.TemporaryDirectory() as root:
            env = write_env(root, tokens={"Kantor": "refresh-token-1"})
            env["TZ"] = "Asia/Jakarta"
            lines = []
            with mock.patch.dict(os.environ, env), \
                    mock.patch.object(google, "request", fake_request([payload])), \
                    mock.patch.object(main.time, "time", return_value=at(21, 7)), \
                    mock.patch("builtins.print",
                               side_effect=lambda *a, **k: lines.append(
                                   " ".join(map(str, a)))):
                status = main.check()
        self.assertEqual(status, 0)
        self.assertTrue(any(line.startswith(
            "Kantor: OK, 1 event berjam, 1 seharian") for line in lines), lines)
        joined = "\n".join(lines)
        for secret in ("raise-this-secret", "akses-rahasia", "refresh-token-1",
                       "google:primary"):
            self.assertNotIn(secret, joined)


if __name__ == "__main__":
    unittest.main()
