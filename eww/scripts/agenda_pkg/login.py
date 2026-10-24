"""One-time Google login: loopback OAuth with PKCE, storing a refresh token."""

import base64
import hashlib
import http.server
import json
import os
import secrets
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import webbrowser

from . import config, fetch, google

SCOPE = "https://www.googleapis.com/auth/calendar.readonly"
DONE = ("<!doctype html><html><body><p>Login selesai. "
        "Jendela ini boleh ditutup.</p></body></html>")
FAILED = ("<!doctype html><html><body><p>Login gagal. "
          "Jendela ini boleh ditutup.</p></body></html>")
INVALID_STORE = "google-tokens.json tidak valid; perbaiki atau hapus dulu"


class _Handler(http.server.BaseHTTPRequestHandler):
    timeout = 5

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/" and not self.server.received:
            self.server.received = True
            self.server.query = urllib.parse.parse_qs(parsed.query)
            body = FAILED if self.server.query.get("error") else DONE
            payload = body.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        self.send_response(404)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, *args):
        pass


class _Server(http.server.HTTPServer):
    def __init__(self, address):
        super().__init__(address, _Handler)
        self.received = False
        self.query = {}


def _challenge(verifier):
    digest = hashlib.sha256(verifier.encode()).digest()
    return base64.urlsafe_b64encode(digest).rstrip(b"=").decode()


def _load_store(path):
    """Stored tokens for merging; None when an existing file is not a token object."""
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, ValueError):
        return None
    if not isinstance(data, dict) or not all(
            isinstance(name, str) and isinstance(token, str)
            for name, token in data.items()):
        return None
    return data


def _save_token(name, refresh, path):
    tokens = _load_store(path)
    if tokens is None:
        print(INVALID_STORE)
        return False
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(path.parent, 0o700)
    tokens[name] = refresh
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".google-tokens-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(tokens, handle, sort_keys=True)
            handle.write("\n")
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
        os.chmod(path, 0o600)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    return True


def run(name, open_browser=webbrowser.open, timeout=300):
    path = config.config_path()
    accounts, _errors, _loose = config.load(path)
    account = next((entry for entry in accounts if entry.name == name), None)
    if account is None or google.calendar_id(account) is None:
        print(f"akun Google {name} tidak ada di config")
        return 1
    token_file = google.tokens_path()
    if _load_store(token_file) is None:
        print(INVALID_STORE)
        return 1
    try:
        client_id, client_secret, token_uri, auth_uri = google.load_client(
            google.client_path())
    except fetch.FeedError as error:
        print(error)
        return 1
    verifier = secrets.token_urlsafe(64)
    state = secrets.token_urlsafe(32)
    params = {"client_id": client_id, "response_type": "code", "scope": SCOPE,
              "access_type": "offline", "prompt": "consent",
              "code_challenge": _challenge(verifier),
              "code_challenge_method": "S256", "state": state}
    if account.email:
        params["login_hint"] = account.email
    server = _Server(("127.0.0.1", 0))
    try:
        redirect_uri = f"http://127.0.0.1:{server.server_address[1]}"
        params["redirect_uri"] = redirect_uri
        url = auth_uri + "?" + urllib.parse.urlencode(params)
        print("Buka tautan ini bila browser tidak terbuka:")
        print(url)
        threading.Thread(target=lambda: _open(open_browser, url), daemon=True).start()
        deadline = time.monotonic() + timeout
        while not server.received:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            server.timeout = remaining
            server.handle_request()
    finally:
        server.server_close()
    if not server.received:
        print("login kedaluwarsa")
        return 1
    query = server.query
    states = query.get("state") or []
    if len(states) != 1 or not secrets.compare_digest(states[0], state):
        print("login ditolak: state tidak cocok")
        return 1
    if query.get("error"):
        print(f"login dibatalkan: {query['error'][0]}")
        return 1
    codes = query.get("code") or []
    if len(codes) != 1 or not codes[0]:
        print("login dibatalkan: tidak ada kode")
        return 1
    try:
        payload = google.request(token_uri, data={
            "code": codes[0], "client_id": client_id,
            "client_secret": client_secret, "redirect_uri": redirect_uri,
            "grant_type": "authorization_code", "code_verifier": verifier})
    except urllib.error.HTTPError as error:
        print(f"login gagal: HTTP {error.code}")
        return 1
    refresh = payload.get("refresh_token") if isinstance(payload, dict) else None
    if not refresh:
        print("Google tidak memberi refresh token")
        return 1
    if not _save_token(name, refresh, token_file):
        return 1
    print(f"{name}: login berhasil; jalankan agenda check")
    return 0


def _open(open_browser, url):
    try:
        open_browser(url)
    except Exception:
        pass
