"""Shared fixtures for the Google Calendar tests: a fake API, never the network."""

import datetime as dt
import io
import json
import os
from pathlib import Path
import urllib.error

from .fixtures import TZ
from agenda_pkg import config

ACCOUNT = config.Account("Kantor", "#4f8cff", "reky@kantor.co.id", "google:primary")
CLIENT = {"installed": {"client_id": "cid", "client_secret": "raise-this-secret",
                         "auth_uri": "https://accounts.example/auth",
                         "token_uri": "https://tokens.example/token"}}


def dtstart(day, hour, minute=0):
    return dt.datetime(2026, 10, day, hour, minute, tzinfo=TZ).isoformat()


def item(**overrides):
    base = {"id": "evt1", "iCalUID": "evt1@google.com", "status": "confirmed",
            "summary": "Standup",
            "start": {"dateTime": dtstart(21, 8)}, "end": {"dateTime": dtstart(21, 8, 30)}}
    base.update(overrides)
    return base


def occurrences(raw, account=ACCOUNT):
    from agenda_pkg import events
    start = dt.datetime(2026, 10, 21, tzinfo=TZ)
    return events.occurrences(raw, account, start, start + dt.timedelta(days=31), TZ)


def fake_request(payloads):
    """A google.request stand-in: token exchange, then event pages in order."""
    seen = []

    def fake(url, data=None, headers=None):
        seen.append((url, data, headers))
        if data is not None:
            return {"access_token": "akses-rahasia"}
        page = payloads.pop(0)
        if isinstance(page, Exception):
            raise page
        return page

    fake.seen = seen
    return fake


def invalid_grant(url, data=None, headers=None):
    raise urllib.error.HTTPError(url, 400, "Bad Request", {},
                                 io.BytesIO(b'{"error": "invalid_grant"}'))


def write_env(root, tokens=None):
    """A temp config dir with a google: account, a client file and optional tokens."""
    root = Path(root)
    (root / "calendars").write_text(
        "Kantor | #4f8cff | reky@kantor.co.id | google:primary\n")
    os.chmod(root / "calendars", 0o600)
    (root / "google-client.json").write_text(json.dumps(CLIENT))
    if tokens is not None:
        (root / "google-tokens.json").write_text(json.dumps(tokens))
    return {"ISLAND_CALENDARS": str(root / "calendars"),
            "XDG_CACHE_HOME": str(root / "cache")}
