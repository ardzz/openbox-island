"""agenda login: loopback OAuth flow with fakes, never the network."""

import base64
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import socket
import stat
import tempfile
import threading
import time
import unittest
from unittest import mock
import urllib.error
import urllib.parse
import urllib.request
from .google_fixtures import CLIENT
from agenda_pkg import google, main

CODE = "kode-rahasia-123"
REFRESH = "refresh-baru-rahasia"
SECRET = CLIENT["installed"]["client_secret"]
TOKEN_URL = CLIENT["installed"]["token_uri"]


def write_config(root, line="Kantor | #4f8cff | reky@kantor.co.id | google:primary\n",
                 tokens=None, client=True):
    root = Path(root)
    (root / "calendars").write_text(line)
    os.chmod(root / "calendars", 0o600)
    if client:
        (root / "google-client.json").write_text(json.dumps(CLIENT))
    if tokens is not None:
        (root / "google-tokens.json").write_text(json.dumps(tokens))
    return {"ISLAND_CALENDARS": str(root / "calendars")}


def browser_that(urls, query):
    """Fake open_browser: GET the redirect URI with QUERY(state) from a thread."""
    def open_browser(url):
        urls.append(url)

        def hit():
            params = urllib.parse.parse_qs(urllib.parse.urlparse(url).query)
            target = (params["redirect_uri"][0] + "/?"
                      + urllib.parse.urlencode(query(params["state"][0])))
            with urllib.request.urlopen(target, timeout=5) as response:
                response.read()

        threading.Thread(target=hit, daemon=True).start()
    return open_browser


def exchange_that(calls, payload):
    def fake(url, data=None, headers=None):
        calls.append((url, data))
        if isinstance(payload, Exception):
            raise payload
        return payload
    return fake


class LoginTests(unittest.TestCase):
    def run_login(self, env, name, browser, fake, timeout=5):
        from agenda_pkg import login
        out = io.StringIO()
        with mock.patch.dict(os.environ, env), \
                mock.patch.object(google, "request", fake), \
                contextlib.redirect_stdout(out):
            status = login.run(name, open_browser=browser, timeout=timeout)
        return status, out.getvalue()

    def test_success_saves_token_and_sends_pkce(self):
        with tempfile.TemporaryDirectory() as root:
            env = write_config(root, tokens={"Lain": "refresh-lama"})
            urls, calls = [], []
            browser = browser_that(urls, lambda state: {"code": CODE, "state": state})
            fake = exchange_that(calls, {"refresh_token": REFRESH, "access_token": "akses"})
            status, output = self.run_login(env, "Kantor", browser, fake)
            tokens = Path(root) / "google-tokens.json"
            saved = json.loads(tokens.read_text())
            mode = stat.S_IMODE(tokens.stat().st_mode)
        self.assertEqual(status, 0)
        self.assertEqual(saved, {"Lain": "refresh-lama", "Kantor": REFRESH})
        self.assertEqual(mode, 0o600)
        self.assertIn("Buka tautan ini bila browser tidak terbuka:", output)
        self.assertIn("Kantor: login berhasil; jalankan agenda check", output)
        for secret in (SECRET, CODE, REFRESH):
            self.assertNotIn(secret, output)
        self.assertEqual(len(urls), 1)
        auth = urllib.parse.urlparse(urls[0])
        self.assertEqual(f"{auth.scheme}://{auth.netloc}{auth.path}",
                         CLIENT["installed"]["auth_uri"])
        params = urllib.parse.parse_qs(auth.query)
        self.assertEqual(params["client_id"], ["cid"])
        self.assertEqual(params["response_type"], ["code"])
        self.assertEqual(params["scope"],
                         ["https://www.googleapis.com/auth/calendar.readonly"])
        self.assertEqual(params["access_type"], ["offline"])
        self.assertEqual(params["prompt"], ["consent"])
        self.assertEqual(params["code_challenge_method"], ["S256"])
        self.assertEqual(params["login_hint"], ["reky@kantor.co.id"])
        self.assertTrue(params["redirect_uri"][0].startswith("http://127.0.0.1:"))
        self.assertTrue(params["state"][0])
        self.assertEqual(len(calls), 1)
        url, data = calls[0]
        self.assertEqual(url, TOKEN_URL)
        self.assertEqual(data["code"], CODE)
        self.assertEqual(data["client_id"], "cid")
        self.assertEqual(data["client_secret"], SECRET)
        self.assertEqual(data["redirect_uri"], params["redirect_uri"][0])
        self.assertEqual(data["grant_type"], "authorization_code")
        digest = hashlib.sha256(data["code_verifier"].encode()).digest()
        challenge = base64.urlsafe_b64encode(digest).rstrip(b"=").decode()
        self.assertEqual(params["code_challenge"], [challenge])

    def test_login_hint_only_with_an_email(self):
        with tempfile.TemporaryDirectory() as root:
            env = write_config(root, "Kantor | #4f8cff | | google:primary\n")
            urls, calls = [], []
            browser = browser_that(urls, lambda state: {"code": CODE, "state": state})
            fake = exchange_that(calls, {"refresh_token": REFRESH})
            status, _ = self.run_login(env, "Kantor", browser, fake)
        self.assertEqual(status, 0)
        params = urllib.parse.parse_qs(urllib.parse.urlparse(urls[0]).query)
        self.assertNotIn("login_hint", params)

    def test_state_mismatch_saves_nothing(self):
        with tempfile.TemporaryDirectory() as root:
            env = write_config(root)
            urls, calls = [], []
            browser = browser_that(urls, lambda state: {"code": CODE, "state": "salah"})
            status, output = self.run_login(
                env, "Kantor", browser, exchange_that(calls, {"refresh_token": REFRESH}))
            exists = (Path(root) / "google-tokens.json").exists()
        self.assertEqual(status, 1)
        self.assertIn("login ditolak: state tidak cocok", output)
        self.assertFalse(exists)
        self.assertEqual(calls, [])

    def test_error_redirect_saves_nothing(self):
        with tempfile.TemporaryDirectory() as root:
            env = write_config(root)
            urls, calls = [], []
            browser = browser_that(
                urls, lambda state: {"error": "access_denied", "state": state})
            status, output = self.run_login(
                env, "Kantor", browser, exchange_that(calls, {"refresh_token": REFRESH}))
            exists = (Path(root) / "google-tokens.json").exists()
        self.assertEqual(status, 1)
        self.assertIn("login dibatalkan: access_denied", output)
        self.assertNotIn(SECRET, output)
        self.assertFalse(exists)
        self.assertEqual(calls, [])

    def test_missing_refresh_token_saves_nothing(self):
        with tempfile.TemporaryDirectory() as root:
            env = write_config(root)
            urls, calls = [], []
            browser = browser_that(urls, lambda state: {"code": CODE, "state": state})
            status, output = self.run_login(
                env, "Kantor", browser, exchange_that(calls, {"access_token": "akses"}))
            exists = (Path(root) / "google-tokens.json").exists()
        self.assertEqual(status, 1)
        self.assertIn("Google tidak memberi refresh token", output)
        self.assertNotIn(CODE, output)
        self.assertFalse(exists)

    def test_http_error_on_exchange_saves_nothing(self):
        error = urllib.error.HTTPError(TOKEN_URL, 503, "Error", {}, io.BytesIO(b""))
        with tempfile.TemporaryDirectory() as root:
            env = write_config(root)
            urls, calls = [], []
            browser = browser_that(urls, lambda state: {"code": CODE, "state": state})
            status, output = self.run_login(
                env, "Kantor", browser, exchange_that(calls, error))
            exists = (Path(root) / "google-tokens.json").exists()
        self.assertEqual(status, 1)
        self.assertIn("login gagal: HTTP 503", output)
        self.assertNotIn(SECRET, output)
        self.assertFalse(exists)

    def test_timeout_saves_nothing(self):
        with tempfile.TemporaryDirectory() as root:
            env = write_config(root)
            urls, calls = [], []
            status, output = self.run_login(
                env, "Kantor", lambda url: urls.append(url),
                exchange_that(calls, {"refresh_token": REFRESH}), timeout=0.3)
            exists = (Path(root) / "google-tokens.json").exists()
        self.assertEqual(status, 1)
        self.assertIn("login kedaluwarsa", output)
        self.assertFalse(exists)
        self.assertEqual(calls, [])

    def test_idle_connection_and_blocked_browser_do_not_block_login(self):
        with tempfile.TemporaryDirectory() as root:
            env, urls, calls, held = write_config(root), [], [], []

            def idle(url):
                urls.append(url)
                params = urllib.parse.parse_qs(urllib.parse.urlparse(url).query)
                host, port = params["redirect_uri"][0].split("://", 1)[1].split(":")
                held.append(socket.create_connection((host, int(port)), timeout=5))

            status, output = self.run_login(
                env, "Kantor", idle, exchange_that(calls, {"refresh_token": REFRESH}),
                timeout=0.6)
            for sock in held:
                sock.close()
            exists = (Path(root) / "google-tokens.json").exists()
        self.assertEqual((status, exists, calls), (1, False, []))
        self.assertIn("login kedaluwarsa", output)
        with tempfile.TemporaryDirectory() as root:
            env, urls, calls = write_config(root), [], []
            release, arrived = threading.Event(), threading.Event()

            def blocked(url):
                params = urllib.parse.parse_qs(urllib.parse.urlparse(url).query)

                def hit():
                    target = (params["redirect_uri"][0] + "/?" + urllib.parse.urlencode(
                        {"code": CODE, "state": params["state"][0]}))
                    urllib.request.urlopen(target, timeout=5).read()
                    arrived.set()

                threading.Thread(target=hit, daemon=True).start()
                release.wait(5)

            try:
                status, output = self.run_login(
                    env, "Kantor", blocked, exchange_that(calls, {"refresh_token": REFRESH}))
            finally:
                release.set()
            saved = json.loads((Path(root) / "google-tokens.json").read_text())
        self.assertTrue(arrived.is_set())
        self.assertEqual((status, saved, len(calls)), (0, {"Kantor": REFRESH}, 1))
        self.assertIn("Kantor: login berhasil; jalankan agenda check", output)

    def test_invalid_existing_token_store_is_preserved(self):
        for content in (b"{ rusak", b"[]", b'{"Kantor": 1}', b"\xff\xfe"):
            with self.subTest(content=content), tempfile.TemporaryDirectory() as root:
                env = write_config(root)
                path = Path(root) / "google-tokens.json"
                path.write_bytes(content)
                urls, calls = [], []
                browser = browser_that(
                    urls, lambda state: {"code": CODE, "state": state})
                status, output = self.run_login(
                    env, "Kantor", browser, exchange_that(calls, {"refresh_token": REFRESH}))
                after = path.read_bytes()
            self.assertEqual(status, 1)
            self.assertIn("google-tokens.json tidak valid; perbaiki atau hapus dulu",
                          output)
            self.assertEqual(after, content)
            for secret in (SECRET, CODE, REFRESH):
                self.assertNotIn(secret, output)

    def test_unknown_and_ical_accounts_return_1(self):
        with tempfile.TemporaryDirectory() as root:
            env = write_config(root, "Pribadi | #34c759 | | https://calendar.example/basic.ics\n")
            urls, calls, fake = [], [], exchange_that([], {"refresh_token": REFRESH})
            status1, out1 = self.run_login(env, "Kantor", lambda u: urls.append(u), fake)
            status2, out2 = self.run_login(env, "Pribadi", lambda u: urls.append(u), fake)
        self.assertEqual((status1, status2, urls), (1, 1, []))
        self.assertIn("akun Google Kantor tidak ada di config", out1)
        self.assertIn("akun Google Pribadi tidak ada di config", out2)

    def test_missing_client_file_returns_1(self):
        with tempfile.TemporaryDirectory() as root:
            env, urls, calls = write_config(root, client=False), [], []
            status, output = self.run_login(env, "Kantor", lambda u: urls.append(u),
                                            exchange_that(calls, {"refresh_token": REFRESH}))
        self.assertEqual(status, 1)
        self.assertIn("google-client.json belum ada", output)
        self.assertEqual((urls, calls), ([], []))


class DispatchTests(unittest.TestCase):
    def test_main_dispatches_login(self):
        with mock.patch("agenda_pkg.login.run", return_value=1) as run, \
                self.assertRaises(SystemExit) as raised:
            main.main(["login", "Kantor"])
        self.assertEqual(raised.exception.code, 1)
        run.assert_called_once_with("Kantor")
